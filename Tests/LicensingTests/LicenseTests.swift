#if !APP_STORE
import Foundation
import Testing
@testable import BambuBarLicensing

private let activationID = "7103adad-ddca-4c23-a523-911fb02fc5f2"
private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

private func granted(activation: String? = activationID, benefit: String = PolarConfiguration.benefitID, expiry: Date? = nil) -> PolarLicense {
    PolarLicense(organizationId: PolarConfiguration.organizationID, benefitId: benefit, status: "granted",
                 expiresAt: expiry, activation: activation.map { .init(id: $0) })
}
private func saved(at date: Date? = fixedNow) -> LicenseRecord {
    LicenseRecord(key: "test-key", activationID: activationID, installationID: "installation", validatedAt: date)
}
private final class MemoryLicense: LicensePersistence {
    var record: LicenseRecord?
    var failsWrites = false
    init(_ record: LicenseRecord? = nil) { self.record = record }
    func load() throws -> LicenseRecord? { record }
    func save(_ record: LicenseRecord?) throws {
        if failsWrites { throw LicenseError.storage(-1) }
        self.record = record
    }
}
private final class FakePolar: LicenseAPI {
    var validation: Result<PolarLicense, Error> = .success(granted())
    var activation: Result<PolarActivation, Error> = .success(.init(id: activationID, licenseKey: granted(activation: nil)))
    var deactivationError: Error?
    var activations = 0
    var deactivations = 0
    var validatedRecord: LicenseRecord?
    var suspendValidation = false
    var pendingValidation: CheckedContinuation<PolarLicense, Error>?
    var validationStarted: (() -> Void)?
    func activate(key: String, installationID: String) async throws -> PolarActivation {
        activations += 1
        return try activation.get()
    }
    func validate(_ record: LicenseRecord) async throws -> PolarLicense {
        validatedRecord = record
        if suspendValidation {
            return try await withCheckedThrowingContinuation {
                pendingValidation = $0
                validationStarted?()
            }
        }
        return try validation.get()
    }
    func deactivate(_ record: LicenseRecord) async throws {
        deactivations += 1
        if let deactivationError { throw deactivationError }
    }
}


private final class PolarHTTPFixture: URLProtocol {
    static var status = 200
    static var response = Data()
    static var lastRequest: URLRequest?
    static var lastBody: [String: Any]?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        Self.lastBody = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.response)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
struct LicenseTests {
    @Test(arguments: [false, true])
    func startupWaitsForValidationBeforeShowingAccessOrActivation(rejected: Bool) async {
        let api = FakePolar()
        api.suspendValidation = true
        let store = LicenseStore(api: api, persistence: MemoryLicense(saved()), now: { fixedNow })
        #expect(store.isInitializing)
        #expect(!store.hasAccess)

        let refresh: Task<Void, Never> = await withCheckedContinuation { started in
            let task = Task { await store.refresh() }
            api.validationStarted = { started.resume(returning: task) }
        }
        // Polar has received the check but has not answered yet.
        #expect(store.isInitializing)
        #expect(store.isBusy)
        #expect(!store.hasAccess)
        api.pendingValidation?.resume(with: rejected ? .failure(LicenseError.rejected) : .success(granted()))
        await refresh.value
        #expect(!store.isInitializing)
        #expect(!store.isBusy)
        #expect(store.hasAccess == !rejected)
    }

    @Test func firstLaunchWithoutLicenseFinishesInitialization() async {
        let store = LicenseStore(api: FakePolar(), persistence: MemoryLicense(), now: { fixedNow })
        #expect(store.isInitializing)
        await store.refresh()
        #expect(!store.isInitializing)
        #expect(!store.hasAccess)
        #expect(store.record == nil)
    }

    @Test func supporterChangesNotifyUpdaterWithoutConsumingAnotherActivation() async {
        let api = FakePolar(), storage = MemoryLicense()
        let store = LicenseStore(api: api, persistence: storage, now: { fixedNow })
        var changes: [Bool] = []
        store.onAccessChange = { changes.append($0) }
        await store.refresh()
        #expect(changes == [false])
        await store.activate(key: "test-key")
        #expect(changes == [false, true])
        await store.refresh()
        #expect(changes == [false, true])
        api.validation = .failure(LicenseError.rejected)
        await store.refresh()
        #expect(changes == [false, true, false])
        api.validation = .success(granted())
        await store.refresh()
        #expect(changes == [false, true, false, true])
        await store.deactivate()
        #expect(changes == [false, true, false, true, false])
        #expect(api.activations == 1)
    }

    @Test func activationPersistsAndRelaunchValidatesSameSlot() async throws {
        let api = FakePolar(), storage = MemoryLicense()
        let first = LicenseStore(api: api, persistence: storage, now: { fixedNow })
        await first.activate(key: "  test-key\n")
        #expect(first.hasAccess)
        #expect(storage.record?.key == "test-key")
        let second = LicenseStore(api: api, persistence: storage, now: { fixedNow })
        #expect(!second.hasAccess)
        await second.refresh()
        #expect(second.hasAccess)
        #expect(api.activations == 1)
        #expect(api.validatedRecord?.activationID == activationID)
        #expect(api.validatedRecord?.installationID == storage.record?.installationID)
    }

    @Test func existingActivationCannotConsumeAnotherSlot() async {
        let api = FakePolar(), storage = MemoryLicense(saved())
        let store = LicenseStore(api: api, persistence: storage, now: { fixedNow })
        await store.activate(key: "another-key")
        #expect(api.activations == 0)
        #expect(storage.record?.key == "test-key")
    }

    @Test func revokedActivationRemovesSupporterBenefitsAndNeverAutoReactivates() async {
        let api = FakePolar(), storage = MemoryLicense(saved())
        let store = LicenseStore(api: api, persistence: storage, now: { fixedNow })
        await store.refresh()
        #expect(store.hasAccess)
        api.validation = .failure(LicenseError.rejected)
        await store.refresh()
        #expect(!store.hasAccess)
        #expect(storage.record?.validatedAt == nil)
        api.validation = .failure(LicenseError.unavailable)
        let restarted = LicenseStore(api: api, persistence: storage, now: { fixedNow })
        await restarted.refresh()
        #expect(!restarted.hasAccess)
        #expect(api.activations == 0)
    }

    @Test func outagesAllowOnlyBoundedOfflineUse() async {
        let api = FakePolar(), storage = MemoryLicense(saved())
        api.validation = .failure(LicenseError.unavailable)
        var clock = fixedNow.addingTimeInterval(6 * 86400)
        let store = LicenseStore(api: api, persistence: storage, now: { clock })
        await store.refresh()
        #expect(store.hasAccess)
        clock = fixedNow.addingTimeInterval(7 * 86400)
        await store.refresh()
        #expect(!store.hasAccess)
        #expect(storage.record?.validatedAt == fixedNow) // Offline retries never extend grace.
    }

    @Test func expiryAndClockRollbackCannotExtendOfflineUse() {
        #expect(!saved().permitsOfflineUse(at: fixedNow.addingTimeInterval(-1)))
        var record = saved()
        record.expiresAt = fixedNow.addingTimeInterval(30)
        #expect(!record.permitsOfflineUse(at: fixedNow.addingTimeInterval(31)))
        #expect(!saved(at: nil).permitsOfflineUse(at: fixedNow))
    }

    @Test func otherProductAndMissingActivationAreRejected() async {
        for license in [granted(benefit: "other-product"), granted(activation: nil), granted(activation: "another-install") , granted(expiry: fixedNow)] {
            let api = FakePolar(), storage = MemoryLicense(saved())
            api.validation = .success(license)
            let store = LicenseStore(api: api, persistence: storage, now: { fixedNow })
            await store.refresh()
            #expect(!store.hasAccess)
            #expect(storage.record?.validatedAt == nil)
        }
    }

    @Test func activationLimitDoesNotUnlockOrSaveKey() async {
        let api = FakePolar(), storage = MemoryLicense()
        api.activation = .failure(LicenseError.activationLimit)
        let store = LicenseStore(api: api, persistence: storage, now: { fixedNow })
        await store.activate(key: "test-key")
        #expect(!store.hasAccess)
        #expect(storage.record == nil)
        #expect(store.message?.contains("deactivate") == true)
    }

    @Test func failedPersistenceRollsBackNewActivation() async {
        let api = FakePolar(), storage = MemoryLicense()
        storage.failsWrites = true
        let store = LicenseStore(api: api, persistence: storage, now: { fixedNow })
        await store.activate(key: "test-key")
        #expect(!store.hasAccess)
        #expect(api.deactivations == 1)
        #expect(storage.record == nil)
    }

    @Test func failedDeactivationKeepsRecordForRetry() async {
        let api = FakePolar(), storage = MemoryLicense(saved())
        let store = LicenseStore(api: api, persistence: storage, now: { fixedNow })
        await store.refresh()
        api.deactivationError = LicenseError.unavailable
        await store.deactivate()
        #expect(store.hasAccess)
        #expect(storage.record != nil)
        api.deactivationError = nil
        await store.deactivate()
        #expect(!store.hasAccess)
        #expect(storage.record == nil)
    }

    @Test func deactivationRemovesSupporterBenefitsEvenIfKeychainDeleteFails() async {
        let api = FakePolar(), storage = MemoryLicense(saved())
        let store = LicenseStore(api: api, persistence: storage, now: { fixedNow })
        await store.refresh()
        storage.failsWrites = true
        await store.deactivate()
        #expect(!store.hasAccess)
        #expect(store.record?.validatedAt == nil)
    }


    @Test func publicClientSendsScopedActivationAndHandlesHTTPFailures() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PolarHTTPFixture.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let api = PolarClient(session: session)
        let json = """
        {"organization_id":"\(PolarConfiguration.organizationID)","benefit_id":"\(PolarConfiguration.benefitID)",
         "status":"granted","expires_at":null,"activation":{"id":"\(activationID)"}}
        """
        PolarHTTPFixture.status = 200
        PolarHTTPFixture.response = Data(json.utf8)
        let result = try await api.validate(saved())
        try result.verify(activationID: activationID, now: fixedNow)
        #expect(PolarHTTPFixture.lastRequest?.url?.absoluteString == "https://api.polar.sh/v1/customer-portal/license-keys/validate")
        #expect(PolarHTTPFixture.lastRequest?.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(PolarHTTPFixture.lastBody?["activation_id"] as? String == activationID)
        #expect(PolarHTTPFixture.lastBody?["benefit_id"] as? String == PolarConfiguration.benefitID)
        #expect(PolarHTTPFixture.lastBody?["organization_id"] as? String == PolarConfiguration.organizationID)
        #expect((PolarHTTPFixture.lastBody?["conditions"] as? [String: String])?["installation_id"] == "installation")
        #expect(PolarHTTPFixture.lastBody?["increment_usage"] == nil)

        PolarHTTPFixture.status = 404
        try await api.deactivate(saved()) // Portal already removed it.
        do { _ = try await api.validate(saved()); Issue.record("404 must reject validation") }
        catch LicenseError.rejected {} catch { Issue.record("Unexpected error: \(error)") }
        PolarHTTPFixture.status = 403
        do { try await api.deactivate(saved()); Issue.record("403 must not clear a local activation") }
        catch LicenseError.rejected {} catch { Issue.record("Unexpected error: \(error)") }
        do { _ = try await api.activate(key: "test-key", installationID: "installation"); Issue.record("403 must reject activation") }
        catch LicenseError.activationLimit {} catch { Issue.record("Unexpected error: \(error)") }
        PolarHTTPFixture.status = 503
        do { _ = try await api.validate(saved()); Issue.record("503 must be an outage") }
        catch LicenseError.unavailable {} catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func actualWireResponseDecodesAndChecksScope() throws {
        let json = """
        {"organization_id":"\(PolarConfiguration.organizationID)","benefit_id":"\(PolarConfiguration.benefitID)",
         "status":"granted","expires_at":"2030-01-01T12:30:00.123456Z","activation":{"id":"\(activationID)"}}
        """
        let license = try PolarClient.decoder().decode(PolarLicense.self, from: Data(json.utf8))
        try license.verify(activationID: activationID, now: fixedNow)
        #expect(license.expiresAt != nil)
        #expect(throws: (any Error).self) { try license.verify(activationID: "wrong", now: fixedNow) }
    }
}
#endif
