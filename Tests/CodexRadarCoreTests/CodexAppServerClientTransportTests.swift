import Foundation
import XCTest
@testable import CodexRadarCore

final class CodexAppServerClientTransportTests: XCTestCase {
    func testExpiredCredentialAfterSuccessfulReadReconnectsOnce() async throws {
        try await checkCredentialRecovery(mode: "after-success", allowsRestart: true, expectedLaunches: 2, succeeds: true)
    }

    func testPersistentCredentialFailureStopsAfterOneReconnect() async throws {
        try await checkCredentialRecovery(mode: "persistent", allowsRestart: true, expectedLaunches: 2, succeeds: false)
    }

    func testBoundSessionNeverReconnectsOnCredentialFailure() async throws {
        try await checkCredentialRecovery(mode: "after-success", allowsRestart: false, expectedLaunches: 1, succeeds: false)
    }

    func testNonAuthenticationFailureDoesNotReconnect() async throws {
        try await checkCredentialRecovery(mode: "network", allowsRestart: true, expectedLaunches: 1, succeeds: false)
    }

    private func checkCredentialRecovery(
        mode: String, allowsRestart: Bool, expectedLaunches: Int, succeeds: Bool
    ) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("radar-auth-recovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("fake-codex")
        let counter = directory.appendingPathComponent("launches")
        let script = """
        #!/usr/bin/python3
        import json,sys,pathlib
        counter=pathlib.Path('\(counter.path)')
        launch=int(counter.read_text())+1 if counter.exists() else 1
        counter.write_text(str(launch))
        reads=0
        for line in sys.stdin:
            request=json.loads(line)
            method=request['method']
            if method=='initialize':
                result={'userAgent':'fake','codexHome':'/tmp','platformFamily':'unix','platformOs':'macos'}
            elif method=='account/rateLimits/read':
                reads+=1
                fail=('\(mode)' in ['persistent','network'] or (launch==1 and reads>1))
                if fail:
                    message='token_expired' if '\(mode)'!='network' else 'connection reset'
                    print(json.dumps({'id':request['id'],'error':{'code':-32000,'message':message}}),flush=True)
                    continue
                result={'rateLimits':{'limitId':'codex','planType':'pro'},'rateLimitsByLimitId':None,'rateLimitResetCredits':None}
            else:
                raise RuntimeError('Unexpected RPC')
            print(json.dumps({'id':request['id'],'result':result}),flush=True)
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let client = CodexAppServerClient(binaryURLProvider: { executable }, allowsAutomaticRestart: allowsRestart)
        if mode == "after-success" {
            let initial = try await client.readRateLimits()
            XCTAssertEqual(initial.rateLimits.planType, "pro")
        }
        do {
            let result = try await client.readRateLimits()
            XCTAssertTrue(succeeds)
            XCTAssertEqual(result.rateLimits.planType, "pro")
        } catch CodexAppServerClient.ClientError.rpcError {
            XCTAssertFalse(succeeds)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        await client.shutdown()
        XCTAssertEqual(try String(contentsOf: counter), String(expectedLaunches))
    }

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
