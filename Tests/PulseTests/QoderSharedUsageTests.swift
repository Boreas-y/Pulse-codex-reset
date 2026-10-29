import Foundation
import Testing
@testable import Pulse

/// Synthetic replies for the two account-page routes. The shared fixture
/// follows the observed team reply's shape, with all identifiers removed and
/// every amount replaced. No browser session or real account is opened here.
private final class QoderSharedFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host,
              ["qoder.com", "qoder.com.cn"].contains(host),
              request.httpMethod == "GET",
              request.value(forHTTPHeaderField: "Origin") == "https://\(host)",
              request.value(forHTTPHeaderField: "Referer") == "https://\(host)/account/usage",
              let cookie = request.value(forHTTPHeaderField: "Cookie"),
              cookie.hasPrefix("sid="), !cookie.contains(";")
        else {
            fail(.badURL)
            return
        }
        let scenario = String(cookie.dropFirst(4))
        let shared = url.path == "/api/v1/me/organization-shared-usages/big_model_credits"
        guard shared || url.path == "/api/v2/me/usages/big_model_credits" else {
            fail(.badURL)
            return
        }
        if scenario == "primary-offline" || (shared && scenario == "shared-offline") {
            fail(.notConnectedToInternet)
            return
        }

        let status: Int
        let body: Data
        if shared {
            switch scenario {
            case "noTeam", "noTeamZero":
                status = 404
                body = Data("{}".utf8)
            case "sharedSpent":
                status = 200
                body = Data(#"{"shared_quota":{"quota_summary":{"used_value":1000,"limit_value":1000,"remaining_value":0}}}"#.utf8)
            case "sharedZero":
                status = 200
                body = Data(#"{"shared_quota":{"quota_summary":{"used_value":0,"limit_value":0,"remaining_value":0}}}"#.utf8)
            case "sharedCamel":
                status = 200
                body = Data(#"{"sharedQuota":{"quotaSummary":{"usedValue":20,"limitValue":1000,"remainingValue":980}}}"#.utf8)
            case "shared-malformed": status = 200; body = Data("<html>sign in</html>".utf8)
            case "shared-missing": status = 200; body = Data("{}".utf8)
            case "shared-null": status = 200; body = Data(#"{"shared_quota":null}"#.utf8)
            case "shared-incomplete":
                status = 200
                body = Data(#"{"shared_quota":{"quota_summary":{"used_value":0}}}"#.utf8)
            case "shared-negative":
                status = 200
                body = Data(#"{"shared_quota":{"quota_summary":{"used_value":-1,"limit_value":1000}}}"#.utf8)
            case "shared-type":
                status = 200
                body = Data(#"{"shared_quota":{"quota_summary":{"used_value":"many","limit_value":1000}}}"#.utf8)
            case "sharedOnly", "personalAndShared":
                status = 200
                body = Self.fixture("qoder-organization-shared")
            default:
                guard scenario.hasPrefix("shared-"),
                      let code = scenario.split(separator: "-").dropFirst().first.flatMap({ Int($0) })
                else {
                    // An inline team pool or a failed personal request must
                    // not be followed by another request.
                    fail(.badURL)
                    return
                }
                status = code
                body = Data("{}".utf8)
            }
        } else if scenario.hasPrefix("primary-"), let code = Int(scenario.dropFirst(8)) {
            status = code
            body = Data("{}".utf8)
        } else if scenario == "inline" {
            status = 200
            body = Self.fixture("qoder-credits-team")
        } else if ["personalAndShared", "noTeam"].contains(scenario) || scenario.hasSuffix("-personal") {
            status = 200
            body = Self.fixture("qoder-credits-parts")
        } else {
            status = 200
            body = Data(#"{"total_quota":{"quota_summary":{"used_value":0,"limit_value":0,"remaining_value":0}}}"#.utf8)
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func fail(_ code: URLError.Code) {
        client?.urlProtocol(self, didFailWithError: URLError(code))
    }

    private static func fixture(_ name: String) -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
              let data = try? Data(contentsOf: url) else { return Data() }
        return data
    }
}

@Suite("Qoder organization shared usage")
struct QoderSharedUsageTests {
    private func fetch(_ scenario: String, site: QoderSite = .international) async -> ProviderUsage {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QoderSharedFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        return await QoderUsageService(
            cookie: "sid=\(scenario); _ga=discarded", site: site, showsParts: true,
            client: QoderClient(session: session)
        ).fetch()
    }

    @Test("The original personal route keeps its HTTP error mapping", arguments: [302, 401, 403, 429, 500, 418])
    func personalErrors(status: Int) async {
        let usage = await fetch("primary-\(status)")
        let reason: ProviderUsage.Unavailability = switch status {
        case 302, 401, 403: .qoderSessionExpired
        case 429: .rateLimited
        case 500: .serverError
        default: .unreadableReply
        }
        #expect(usage.state == .unavailable(reason))
    }

    @Test("A personal transport failure remains a failure")
    func personalTransportFailure() async {
        #expect(await fetch("primary-offline").state == .unavailable(.unreachable))
    }

    @Test("An inline team pool needs no second lookup")
    func inlineTeamPool() async {
        let usage = await fetch("inline")
        #expect(usage.state == .live)
        #expect(usage.windows.map(\.kind) == [.credits, .sharedCredits])
        #expect(usage.windows.last?.amounts == .init(used: 200, remaining: 800, limit: 1000))
    }

    @Test("A team-only account reads the member's shared quota on the chosen host", arguments: [
        QoderSite.international, .china
    ])
    func teamOnlyAccount(site: QoderSite) async throws {
        let usage = await fetch("sharedOnly", site: site)
        #expect(usage.state == .live)
        #expect(usage.windows.count == 1)
        let window = try #require(usage.windows.first)
        #expect(window.id == "qoder.shared")
        #expect(window.kind == .sharedCredits)
        #expect(window.amounts == .init(used: 20, remaining: 980, limit: 1000))
        #expect(window.usedFraction == 0.02)
        #expect(window.resetsAt == nil)
        #expect(!window.isExhausted)
        #expect(usage.sourceScope?.organization == site.host)
    }

    @Test("Personal parts and the team pool remain separate")
    func personalAndShared() async {
        let usage = await fetch("personalAndShared")
        #expect(usage.state == .live)
        #expect(usage.windows.map(\.id) == [
            "qoder.credits", "qoder.plan", "qoder.pack", "qoder.dedicated", "qoder.shared"
        ])
        #expect(usage.windows.first?.amounts == .init(used: 6068, remaining: 7932, limit: 14000))
        #expect(usage.windows.last?.amounts == .init(used: 20, remaining: 980, limit: 1000))
    }

    @Test("The shared reply accepts either key spelling")
    func camelCaseShared() async {
        #expect(await fetch("sharedCamel").windows.first?.amounts == .init(used: 20, remaining: 980, limit: 1000))
    }

    @Test("An exhausted team allowance is still a reported allowance")
    func exhaustedTeamPool() async {
        let usage = await fetch("sharedSpent")
        #expect(usage.state == .live)
        #expect(usage.windows.first?.isExhausted == true)
        #expect(usage.windows.first?.amounts == .init(used: 1000, remaining: 0, limit: 1000))
    }

    @Test("A confirmed zero team allowance does not draw a ring")
    func zeroTeamPool() async {
        #expect(await fetch("sharedZero").state == .unavailable(.qoderNoCredits))
    }

    @Test("An unavailable team route leaves the personal allowance intact")
    func notOnATeam() async {
        let usage = await fetch("noTeam")
        #expect(usage.state == .live)
        #expect(usage.windows.map(\.id) == ["qoder.credits", "qoder.plan", "qoder.pack", "qoder.dedicated"])
        #expect(await fetch("noTeamZero").state == .unavailable(.qoderNoCredits))
    }

    @Test("A failed shared lookup keeps the previous team reading", arguments: [
        "shared-302", "shared-401", "shared-403", "shared-429", "shared-500", "shared-418",
        "shared-offline", "shared-malformed", "shared-missing", "shared-null", "shared-incomplete",
        "shared-negative", "shared-type", "shared-500-personal"
    ])
    func sharedFailureRetainsCache(scenario: String) async {
        let file = URL.temporaryDirectory.appending(path: "PulseQoderShared-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let cache = UsageCache(file: file)
        var old = ProviderUsage(
            account: AccountKey(.qoder), windows: QoderUsageService.windows(from: .init(
                personal: .init(used: 0, limit: 0, remaining: 0),
                shared: .init(used: 20, limit: 1000, remaining: 980), resetsAt: nil
            ), at: Date()), observedAt: Date().addingTimeInterval(-60), state: .live,
            plan: nil, creditBalance: nil
        )
        old.sourceScope = QoderUsageService.scope(
            site: .international, cookie: "sid=\(scenario); _ga=discarded"
        )
        _ = await cache.reconciled(old)

        let raw = await fetch(scenario)
        let reason: ProviderUsage.Unavailability = switch scenario {
        case "shared-302", "shared-401", "shared-403": .qoderSessionExpired
        case "shared-429": .rateLimited
        case "shared-500", "shared-500-personal": .serverError
        case "shared-offline": .unreachable
        default: .unreadableReply
        }
        #expect(raw.state == .unavailable(reason))
        let displayed = await cache.reconciled(raw)
        #expect(displayed.state == .stale)
        #expect(displayed.windows == old.windows)
        #expect(await UsageCache(file: file).lastReading(for: old.account)?.windows == old.windows)
    }
}
