import Foundation
import XCTest
@testable import CodexRadarCore
@testable import CodexRadarSentinel

@MainActor
final class RadarInsightsOrchestrationTests: XCTestCase {
    func testRefreshIsIndependentSingleFlightThrottledAndKeepsNewestGoodData()
        async throws
    {
        let identifier = UUID().uuidString
        let suiteName = "com.codexradar.sentinel.insights-tests.\(identifier)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(false, forKey: "automaticUpdatesEnabled")
        defaults.set(false, forKey: "resetCreditAutoRefreshEnabled")
        defaults.set(false, forKey: "predictionNotificationsEnabled")
        defaults.set(false, forKey: "iqNotificationsEnabled")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "codex-radar-insights-tests-\(identifier)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RadarInsightsStoreURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let controller = RadarInsightsStoreURLProtocol.controller
        let uptime = RadarInsightsTestUptime(100)
        let appServer = RadarInsightsTestAppServer()
        controller.reset(
            mode: .suspended(
                insightsPayload(
                    iq: 91,
                    updatedAt: "2026-07-26T02:00:00Z"
                )
            )
        )

        let baseURL = URL(string: "https://sentinel-insights.test/")!
        let store = SentinelStore(
            defaults: defaults,
            radarClient: CodexRadarClient(
                baseURL: baseURL,
                radarInsightsURL: baseURL.appending(
                    path: "api/v1/radar-insights"
                ),
                session: session
            ),
            appServerClient: appServer,
            resetCreditProtectionLedgerStore:
                ResetCreditProtectionLedgerStore(
                    url: directory.appendingPathComponent("ledger.json")
                ),
            resetCreditProtectionAuthorizationStore:
                ResetCreditProtectionAuthorizationStore(
                    url: directory.appendingPathComponent(
                        "authorization.json"
                    ),
                    dispatchLockURL: directory.appendingPathComponent(
                        "authorization.lock"
                    )
                ),
            resetCreditProtectionProcessLockURL: directory
                .appendingPathComponent("process.lock"),
            radarInsightsUptime: {
                uptime.value
            },
            resetCreditProtectionDestructiveActionsAllowed: false
        )
        defer {
            controller.releaseSuspendedRequest()
            store.stop()
            session.invalidateAndCancel()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }

        store.start()
        store.refreshNow()
        store.refreshNow()

        try await waitUntil {
            let appServerSnapshot = await appServer.snapshot()
            return controller.snapshot().requestCount == 1
                && appServerSnapshot.rateLimitReadCount >= 1
                && store.dashboardState.rateLimits != nil
        }
        XCTAssertEqual(controller.snapshot().completionCount, 0)
        XCTAssertNil(store.dashboardState.radarInsights)

        controller.releaseSuspendedRequest()
        try await waitUntil {
            self.firstRecommendationIQ(in: store) == 91
        }

        let coreReadsBeforeThrottle = await appServer.snapshot()
            .rateLimitReadCount
        store.refreshNow()
        store.refreshNow()
        try await waitUntil {
            await appServer.snapshot().rateLimitReadCount
                > coreReadsBeforeThrottle
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(controller.snapshot().requestCount, 1)

        uptime.advance(by: 601)
        controller.configure(
            mode: .immediate(
                Data(
                    """
                    {
                      "schema": 2,
                      "recommendations": [],
                      "degradation_alerts": []
                    }
                    """.utf8
                )
            )
        )
        store.refreshNow()
        try await waitUntil {
            controller.snapshot().completionCount == 2
        }
        XCTAssertEqual(firstRecommendationIQ(in: store), 91)
        XCTAssertNil(store.dashboardState.lastError)

        let coreReadsBeforeFailedThrottle = await appServer.snapshot()
            .rateLimitReadCount
        store.refreshNow()
        try await waitUntil {
            await appServer.snapshot().rateLimitReadCount
                > coreReadsBeforeFailedThrottle
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(controller.snapshot().requestCount, 2)

        uptime.advance(by: 601)
        controller.configure(
            mode: .immediate(
                insightsPayload(
                    iq: 20,
                    updatedAt: "2026-07-26T01:00:00Z"
                )
            )
        )
        store.refreshNow()
        try await waitUntil {
            controller.snapshot().completionCount == 3
        }
        XCTAssertEqual(firstRecommendationIQ(in: store), 91)

        uptime.advance(by: 601)
        controller.configure(
            mode: .immediate(
                insightsPayload(
                    iq: 95,
                    updatedAt: "2026-07-26T03:00:00Z"
                )
            )
        )
        store.refreshNow()
        try await waitUntil {
            self.firstRecommendationIQ(in: store) == 95
        }

        uptime.set(50)
        controller.configure(
            mode: .immediate(
                insightsPayload(
                    iq: 96,
                    updatedAt: "2026-07-26T04:00:00Z"
                )
            )
        )
        store.refreshNow()
        try await waitUntil {
            self.firstRecommendationIQ(in: store) == 96
        }

        let finalNetworkSnapshot = controller.snapshot()
        let finalAppServerSnapshot = await appServer.snapshot()
        XCTAssertEqual(finalNetworkSnapshot.requestCount, 5)
        XCTAssertEqual(finalNetworkSnapshot.sensitiveHeaderCount, 0)
        XCTAssertEqual(finalAppServerSnapshot.consumeCallCount, 0)
    }

    private func firstRecommendationIQ(
        in store: SentinelStore
    ) -> Double? {
        store.dashboardState.radarInsights?
            .recommendations.first?
            .validItems.first?
            .iq
    }

    private func insightsPayload(
        iq: Double,
        updatedAt: String
    ) -> Data {
        Data(
            """
            {
              "schema": 1,
              "generated_at": "\(updatedAt)",
              "source_updated_at": "\(updatedAt)",
              "recommendations": [
                {
                  "key": "daily_development",
                  "items": [
                    {
                      "model": "gpt-5.6-sol",
                      "effort": "medium",
                      "iq": \(iq),
                      "average_cost_usd": 3.82,
                      "average_duration_minutes": 16
                    }
                  ]
                }
              ],
              "degradation_alerts": []
            }
            """.utf8
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 3,
        condition: () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw RadarInsightsTestError.timedOut
    }
}

private enum RadarInsightsTestError: Error {
    case timedOut
    case unexpectedAccountRead
    case unexpectedConsume
}

private final class RadarInsightsTestUptime: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: TimeInterval

    init(_ value: TimeInterval) {
        storedValue = value
    }

    var value: TimeInterval {
        lock.lock()
        defer {
            lock.unlock()
        }
        return storedValue
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        storedValue += interval
        lock.unlock()
    }

    func set(_ value: TimeInterval) {
        lock.lock()
        storedValue = value
        lock.unlock()
    }
}

private actor RadarInsightsTestAppServer:
    ResetCreditProtectionAppServerServing
{
    struct Snapshot {
        let rateLimitReadCount: Int
        let consumeCallCount: Int
    }

    private let response = RateLimitResponse(
        rateLimits: RateLimitSnapshot(
            limitId: AppConstants.codexLimitID,
            limitName: "Codex",
            primary: RateLimitWindow(
                usedPercent: 15,
                windowDurationMins: AppConstants.weeklyWindowMinutes,
                resetsAt: Int(Date().addingTimeInterval(86_400).timeIntervalSince1970)
            ),
            secondary: nil,
            credits: nil,
            planType: "pro",
            rateLimitReachedType: nil
        ),
        rateLimitsByLimitId: nil,
        rateLimitResetCredits: nil
    )
    private var rateLimitReadCount = 0
    private var consumeCallCount = 0

    func readRateLimits() async throws -> RateLimitResponse {
        rateLimitReadCount += 1
        return response
    }

    func readAccount() async throws -> CodexAccountResponse {
        throw RadarInsightsTestError.unexpectedAccountRead
    }

    func consumeResetCredit(
        creditID: String,
        idempotencyKey: String,
        authorization: ResetCreditProtectionDispatchAuthorization
    ) async throws -> ResetCreditConsumeResponse {
        consumeCallCount += 1
        throw RadarInsightsTestError.unexpectedConsume
    }

    func snapshot() -> Snapshot {
        Snapshot(
            rateLimitReadCount: rateLimitReadCount,
            consumeCallCount: consumeCallCount
        )
    }
}

private final class RadarInsightsStoreURLProtocol:
    URLProtocol,
    @unchecked Sendable
{
    static let controller = RadarInsightsURLProtocolController()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        guard request.url?.path == "/api/v1/radar-insights" else {
            deliver(data: Data("{}".utf8), statusCode: 200)
            return
        }

        let plan = Self.controller.begin(request: request)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if let gate = plan.gate {
                _ = gate.wait(timeout: .now() + 5)
            }
            self?.deliver(data: plan.data, statusCode: plan.statusCode)
            Self.controller.recordCompletion()
        }
    }

    override func stopLoading() {}

    private func deliver(data: Data, statusCode: Int) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(
            self,
            didReceive: response,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

private final class RadarInsightsURLProtocolController:
    @unchecked Sendable
{
    enum Mode {
        case suspended(Data)
        case immediate(Data)
    }

    struct Plan: @unchecked Sendable {
        let data: Data
        let statusCode: Int
        let gate: DispatchSemaphore?
    }

    struct Snapshot {
        let requestCount: Int
        let completionCount: Int
        let sensitiveHeaderCount: Int
    }

    private let lock = NSLock()
    private var mode = Mode.immediate(Data())
    private var suspendedGate: DispatchSemaphore?
    private var requestCount = 0
    private var completionCount = 0
    private var sensitiveHeaderCount = 0

    func reset(mode: Mode) {
        lock.lock()
        self.mode = mode
        suspendedGate = Self.gate(for: mode)
        requestCount = 0
        completionCount = 0
        sensitiveHeaderCount = 0
        lock.unlock()
    }

    func configure(mode: Mode) {
        lock.lock()
        self.mode = mode
        suspendedGate = Self.gate(for: mode)
        lock.unlock()
    }

    func begin(request: URLRequest) -> Plan {
        lock.lock()
        defer {
            lock.unlock()
        }
        requestCount += 1
        if request.value(forHTTPHeaderField: "Authorization") != nil
            || request.value(forHTTPHeaderField: "Cookie") != nil {
            sensitiveHeaderCount += 1
        }
        switch mode {
        case .suspended(let data):
            return Plan(
                data: data,
                statusCode: 200,
                gate: suspendedGate
            )
        case .immediate(let data):
            return Plan(
                data: data,
                statusCode: 200,
                gate: nil
            )
        }
    }

    func recordCompletion() {
        lock.lock()
        completionCount += 1
        lock.unlock()
    }

    func releaseSuspendedRequest() {
        lock.lock()
        let gate = suspendedGate
        suspendedGate = nil
        lock.unlock()
        gate?.signal()
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer {
            lock.unlock()
        }
        return Snapshot(
            requestCount: requestCount,
            completionCount: completionCount,
            sensitiveHeaderCount: sensitiveHeaderCount
        )
    }

    private static func gate(for mode: Mode) -> DispatchSemaphore? {
        if case .suspended = mode {
            return DispatchSemaphore(value: 0)
        }
        return nil
    }
}
