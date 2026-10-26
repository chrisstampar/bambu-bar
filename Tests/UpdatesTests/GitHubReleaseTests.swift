import Foundation
import Testing
@testable import BambuBarUpdates

struct GitHubReleaseTests {
    private func release(_ tag: String, draft: Bool = false, prerelease: Bool = false, feed: Bool = false) -> GitHubRelease {
        GitHubRelease(tagName: tag, draft: draft, prerelease: prerelease, assets: feed ? [.init(name: "appcast.xml")] : [])
    }

    @Test func oldReleaseWithoutFeedDoesNotOfferDowngrade() throws {
        let latest = release("v1.3.1")
        #expect(try latest.newerVersion(than: "1.5.0") == nil)
        #expect(!latest.hasUpdateFeed)
    }

    @Test func versionsCompareNumerically() throws {
        #expect(try release("v1.10.0").newerVersion(than: "1.9.0") == "1.10.0")
        #expect(try release("1.5.0").newerVersion(than: "1.5.0") == nil)
        #expect(try release("v2.0.0").newerVersion(than: "1.99.99") == "2.0.0")
    }

    @Test func draftsPrereleasesAndMalformedVersionsAreNotOffered() throws {
        #expect(try release("v2.0.0", draft: true).newerVersion(than: "1.5.0") == nil)
        #expect(try release("v2.0.0-beta", prerelease: true).newerVersion(than: "1.5.0") == nil)
        #expect(throws: GitHubReleaseError.self) { try release("latest").newerVersion(than: "1.5.0") }
        #expect(throws: GitHubReleaseError.self) { try release("v2..0").newerVersion(than: "1.5.0") }
    }

    @Test func decodesGitHubWireFormatAndIdentifiesSignedFeed() throws {
        let data = Data(#"{"tag_name":"v1.6.0","draft":false,"prerelease":false,"assets":[{"name":"Bambu-Bar-1.6.0-macos.zip"},{"name":"appcast.xml"}]}"#.utf8)
        let latest = try JSONDecoder().decode(GitHubRelease.self, from: data)
        #expect(try latest.newerVersion(than: "1.5.0") == "1.6.0")
        #expect(latest.hasUpdateFeed)
    }
}
