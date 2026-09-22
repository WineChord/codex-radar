import Foundation
import XCTest
@testable import CodexRadarCore

final class CodexAppServerClientTransportTests: XCTestCase {
    func testClosedInputPipeReturnsProcessUnavailableAndNextReadRestarts()
        async throws
    {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "codex-radar-closed-input-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let executable = directory.appendingPathComponent("fake-codex")
        let launchCount = directory.appendingPathComponent("launch-count")
        let script = """
        #!/bin/sh
        count=0
        if [ -f '\(launchCount.path)' ]; then
          IFS= read -r count < '\(launchCount.path)'
        fi
        count=$((count + 1))
        printf '%s\\n' "$count" > '\(launchCount.path)'
        IFS= read -r request
        request_id="$(printf '%s' "$request" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
        if [ "$count" -eq 1 ]; then
          exec 0<&-
          printf '{"id":%s,"result":{"userAgent":"fake","codexHome":"/tmp","platformFamily":"unix","platformOs":"macos"}}\\n' "$request_id"
          sleep 5
          exit 0
        fi
        printf '{"id":%s,"result":{"userAgent":"fake","codexHome":"/tmp","platformFamily":"unix","platformOs":"macos"}}\\n' "$request_id"
        IFS= read -r request
        request_id="$(printf '%s' "$request" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
        printf '{"id":%s,"result":{"rateLimits":{"limitId":"codex","limitName":"Codex","primary":null,"secondary":null,"credits":null,"planType":"pro","rateLimitReachedType":null},"rateLimitsByLimitId":null,"rateLimitResetCredits":null}}\\n' "$request_id"
        while IFS= read -r _; do :; done
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let client = CodexAppServerClient(
            binaryURLProvider: { executable }
        )

        do {
            _ = try await client.readRateLimits()
            XCTFail("Expected the closed input pipe to reject the request")
        } catch CodexAppServerClient.ClientError.processUnavailable {
            // Expected: a closed child pipe is reported instead of aborting.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let isLive = await client.hasLiveInitializedSession()
        XCTAssertFalse(isLive)

        let response = try await client.readRateLimits()
        XCTAssertEqual(response.rateLimits.planType, "pro")
        await client.shutdown()
        let launches = try String(contentsOf: launchCount, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(launches, "2")
    }
}
