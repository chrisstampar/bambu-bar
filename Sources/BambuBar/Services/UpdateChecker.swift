import AppKit
import Foundation
import Observation
import Sparkle

/// In-app updates through Sparkle. Once a day it reads the appcast attached to the latest GitHub release (no account,
/// no identifiers). A newer version opens Sparkle's window with its release notes and Install Update, Skip This
/// Version or Remind Me Later; installing downloads it, checks its EdDSA signature and Developer ID, swaps the app
/// and relaunches it.
@MainActor
@Observable
final class UpdateChecker: NSObject {
    static let shared = UpdateChecker()

    struct Release: Equatable {
        let version: String
    }

    enum State: Equatable {
        case idle, checking, upToDate, available(Release), failed(String)
    }

    nonisolated static let repository = "rolottr/bambu-bar"

    /// `-UpdateFeedURL <url>` on the command line points a build at another appcast, to try an update end to end.
    /// The update still has to carry this app's EdDSA signature.
    nonisolated private static var feedOverride: String? {
        UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)["UpdateFeedURL"] as? String
    }

    let currentVersion = AppInfo.version
    private(set) var state: State = .idle
    private(set) var lastChecked: Date?
    /// Hidden from the menu bar panel for this run ("Later", or Remind Me Later in Sparkle's window).
    private(set) var offerDismissed = false
    private(set) var skippedVersion: String?
    private(set) var isRunning = false
    @ObservationIgnored private var controller: SPUStandardUpdaterController!

    var checksAutomatically = true {
        didSet { if isRunning { updater.automaticallyChecksForUpdates = checksAutomatically } }
    }

    var downloadsAutomatically = false {
        didSet { if isRunning { updater.automaticallyDownloadsUpdates = downloadsAutomatically } }
    }

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
    }

    private var updater: SPUUpdater { controller.updater }

    var available: Release? {
        if case .available(let release) = state { return release }
        return nil
    }

    /// The release to offer in the menu bar panel: not skipped and not put off for later.
    var offered: Release? {
        guard let release = available, !offerDismissed, release.version != skippedVersion else { return nil }
        return release
    }

    /// Starts Sparkle's daily schedule. Demo, showcase and probe runs leave it off.
    func start() {
        guard !isRunning, !LaunchContext.isDeveloperRun || Self.feedOverride != nil else { return }
        migrateSettings()
        controller.startUpdater()
        isRunning = true
        syncSettings()
    }

    /// Looks for a newer version without showing Sparkle's window; the pages show the result.
    func check() {
        guard isRunning, state != .checking else { return }
        if updater.sessionInProgress { return showUpdate() }
        state = .checking
        updater.checkForUpdateInformation()
    }

    /// "Check for Updates…" and the Update buttons: Sparkle's window with the release notes, or "You're up to date".
    func showUpdate() {
        guard isRunning else { return }
        offerDismissed = true
        controller.checkForUpdates(nil)
    }

    func dismissOffer() { offerDismissed = true }

    /// The checkbox in Sparkle's window can change automatic downloads behind the toggles' back.
    private func syncSettings() {
        checksAutomatically = updater.automaticallyChecksForUpdates
        downloadsAutomatically = updater.automaticallyDownloadsUpdates
        lastChecked = updater.lastUpdateCheckDate
    }

    /// Up to 1.3 the app checked GitHub itself; keep a switched-off automatic check switched off.
    private func migrateSettings() {
        let defaults = UserDefaults.standard
        if let automatic = defaults.object(forKey: "updateChecksAutomatically") as? Bool {
            updater.automaticallyChecksForUpdates = automatic
        }
        for key in ["updateChecksAutomatically", "updateLastChecked", "updateSkippedVersion"] {
            defaults.removeObject(forKey: key)
        }
    }

    private func found(_ item: SUAppcastItem) {
        let release = Release(version: item.displayVersionString)
        if available != release { offerDismissed = false }
        state = .available(release)
    }
}

// Sparkle calls its delegates on the main thread.
extension UpdateChecker: SPUUpdaterDelegate {
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? { Self.feedOverride }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        MainActor.assumeIsolated { found(item) }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        MainActor.assumeIsolated { state = .upToDate }
    }

    nonisolated func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice,
                             forUpdate updateItem: SUAppcastItem, state: SPUUserUpdateState) {
        let version = updateItem.displayVersionString
        MainActor.assumeIsolated {
            switch choice {
            case .skip: skippedVersion = version
            case .dismiss: offerDismissed = true
            case .install: break
            @unknown default: break
            }
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        let code = (error as NSError?).flatMap { $0.domain == SUSparkleErrorDomain ? $0.code : nil }
        let failed = error != nil && code != Int(SUError.noUpdateError.rawValue)
            && code != Int(SUError.installationCanceledError.rawValue)
        MainActor.assumeIsolated {
            if state == .checking {
                state = failed ? .failed(String(localized: "Couldn’t reach GitHub. Check your connection and try again.")) : .upToDate
            }
            syncSettings()
        }
    }
}

extension UpdateChecker: SPUStandardUserDriverDelegate {
    /// A menu bar app has no window to wait for: Sparkle shows its window right away (in front shortly after launch or
    /// while the Mac sat idle, otherwise behind other apps) and the menu bar panel offers the update too.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                                          andInImmediateFocus immediateFocus: Bool) -> Bool {
        true
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {
        MainActor.assumeIsolated { found(update) }
    }
}
