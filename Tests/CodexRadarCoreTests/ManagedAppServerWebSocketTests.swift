import Foundation
import XCTest
@testable import CodexRadarCore

final class ManagedAppServerWebSocketTests: XCTestCase {
    func testHandshakeUsesRFC6455AcceptAndPreservesFirstFrame() throws {
        let handshake = ManagedAppServerHandshake(
            key: "dGhlIHNhbXBsZSBub25jZQ=="
        )
        XCTAssertTrue(
            String(decoding: handshake.request, as: UTF8.self)
                .hasSuffix("\r\n\r\n")
        )
        XCTAssertEqual(
            handshake.expectedAccept,
            "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
        )

        let frame = serverFrame(payload: Data("ready".utf8))
        let response = handshakeResponse(
            accept: "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=",
            connection: "keep-alive, Upgrade"
        ) + frame
        var buffer = Data(response.prefix(24))
        XCTAssertFalse(try handshake.consumeResponse(from: &buffer))
        buffer.append(response.dropFirst(24))
        XCTAssertTrue(try handshake.consumeResponse(from: &buffer))
        XCTAssertEqual(buffer, frame)
    }

    func testHandshakeRejectsWrongServerProof() {
        let handshake = ManagedAppServerHandshake(key: "known-key")
        var response = handshakeResponse(accept: "wrong")

        XCTAssertThrowsError(try handshake.consumeResponse(from: &response)) {
            XCTAssertEqual(
                $0 as? ManagedAppServerTransportError,
                .invalidHandshake
            )
        }
    }

    func testClientFramesAreMaskedAcrossPayloadLengthBoundaries() throws {
        let mask: [UInt8] = [0x37, 0xFA, 0x21, 0x3D]
        for payload in [
            Data(),
            Data(repeating: 0x61, count: 125),
            Data(repeating: 0x62, count: 126),
            Data(repeating: 0x63, count: 70_000),
        ] {
            let frame = ManagedAppServerWebSocketCodec.clientFrame(
                payload: payload,
                mask: mask
            )
            let decoded = try decodeClientFrame(frame)
            XCTAssertEqual(decoded.opcode, 0x1)
            XCTAssertEqual(decoded.payload, payload)
        }
    }

    func testCodecReassemblesTextAndAnswersInterleavedPing() throws {
        var codec = ManagedAppServerWebSocketCodec()
        let bytes = serverFrame(
            payload: Data("hel".utf8),
            opcode: 0x1,
            isFinal: false
        ) + serverFrame(payload: Data("?".utf8), opcode: 0x9)
            + serverFrame(payload: Data("lo".utf8), opcode: 0x0)

        let events = try codec.append(bytes)
        XCTAssertEqual(
            events,
            [.ping(Data("?".utf8)), .text(Data("hello".utf8))]
        )
    }

    func testCodecRejectsMaskedServerFrame() {
        var codec = ManagedAppServerWebSocketCodec()
        let masked = ManagedAppServerWebSocketCodec.clientFrame(
            payload: Data("invalid".utf8),
            mask: [1, 2, 3, 4]
        )
        XCTAssertThrowsError(try codec.append(masked)) {
            XCTAssertEqual(
                $0 as? ManagedAppServerTransportError,
                .invalidFrame
            )
        }
    }

    func testClientReadsRateLimitsThroughManagedProxy() async throws {
        let fixture = try makeFakeCodex(managedHandshakeSucceeds: true)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let socket = fixture.directory.appendingPathComponent("control.sock")
        let client = CodexAppServerClient(
            binaryURLProvider: { fixture.executable },
            allowsAutomaticRestart: false,
            managedControlSocketURLProvider: { socket }
        )

        let response = try await client.readRateLimits()
        await client.shutdown()

        XCTAssertEqual(
            RateLimitDashboard(response: response).weeklyRemainingPercent,
            93
        )
        XCTAssertEqual(response.rateLimitResetCredits?.availableCount, 2)
        let records = try transcriptRecords(at: fixture.transcript)
        let arguments = try XCTUnwrap(records.first?["args"] as? [String])
        XCTAssertEqual(
            arguments,
            ["app-server", "proxy", "--sock", socket.path]
        )
        XCTAssertEqual(
            records.compactMap { $0["method"] as? String },
            ["initialize", "initialized", "account/rateLimits/read"]
        )
        XCTAssertTrue(records.dropFirst().allSatisfy {
            ($0["masked"] as? Bool) == true
        })
    }

    func testInvalidManagedHandshakeFallsBackToStandaloneStdio() async throws {
        let fixture = try makeFakeCodex(managedHandshakeSucceeds: false)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let socket = fixture.directory.appendingPathComponent("control.sock")
        let client = CodexAppServerClient(
            binaryURLProvider: { fixture.executable },
            allowsAutomaticRestart: false,
            managedControlSocketURLProvider: { socket }
        )

        let account = try await client.readAccount()
        await client.shutdown()

        XCTAssertEqual(account.account?.planType, "pro")
        let records = try transcriptRecords(at: fixture.transcript)
        let invocations = records.compactMap { $0["args"] as? [String] }
        XCTAssertEqual(invocations.count, 2)
        XCTAssertEqual(
            invocations[0],
            ["app-server", "proxy", "--sock", socket.path]
        )
        XCTAssertEqual(
            invocations[1],
            ["app-server", "--listen", "stdio://"]
        )
        XCTAssertEqual(
            records.compactMap { $0["method"] as? String },
            ["initialize", "account/read"]
        )
    }

    func testVerifiedOneShotManagedSessionNeverCrossesProcessBoundary()
        async throws
    {
        let fixture = try makeFakeCodex(
            managedHandshakeSucceeds: true,
            managedExitsAfterAccountRead: true
        )
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let socket = fixture.directory.appendingPathComponent("control.sock")
        let client = CodexAppServerClient(
            binaryURLProvider: { fixture.executable },
            allowsAutomaticRestart: false,
            managedControlSocketURLProvider: { socket }
        )

        _ = try await client.readAccount()
        let deadline = Date().addingTimeInterval(2)
        while await client.hasLiveInitializedSession(), Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let hasLiveSession = await client.hasLiveInitializedSession()
        XCTAssertFalse(hasLiveSession)

        do {
            _ = try await client.readRateLimits()
            XCTFail("Expected the one-shot client to reject a new process")
        } catch CodexAppServerClient.ClientError.processUnavailable {
            // Expected: preflight and a later write cannot cross sessions.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        await client.shutdown()

        let records = try transcriptRecords(at: fixture.transcript)
        XCTAssertEqual(
            records.compactMap { $0["args"] as? [String] }.count,
            1
        )
        XCTAssertEqual(
            records.compactMap { $0["method"] as? String },
            ["initialize", "initialized", "account/read"]
        )
    }

    func testLocatorRejectsRegularFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "codex-radar-managed-locator-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        let controlDirectory = directory.appendingPathComponent(
            "app-server-control",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: controlDirectory,
            withIntermediateDirectories: true
        )
        let candidate = controlDirectory.appendingPathComponent(
            "app-server-control.sock"
        )
        try Data().write(to: candidate)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: candidate.path
        )

        XCTAssertNil(
            CodexManagedAppServerLocator.findControlSocket(
                environment: ["CODEX_HOME": directory.path],
                homeDirectory: URL(fileURLWithPath: "/unused")
            )
        )
    }

    private func makeFakeCodex(
        managedHandshakeSucceeds: Bool,
        managedExitsAfterAccountRead: Bool = false
    ) throws -> (
        directory: URL,
        executable: URL,
        transcript: URL
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "codex-radar-managed-proxy-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let executable = directory.appendingPathComponent("fake-codex")
        let transcript = directory.appendingPathComponent("transcript.jsonl")
        let transcriptLiteral = String(reflecting: transcript.path)
        let succeedsLiteral = managedHandshakeSucceeds ? "True" : "False"
        let exitsLiteral = managedExitsAfterAccountRead ? "True" : "False"
        let script = """
        #!/usr/bin/python3
        import base64
        import hashlib
        import json
        import struct
        import sys

        transcript = \(transcriptLiteral)
        managed_handshake_succeeds = \(succeedsLiteral)
        managed_exits_after_account_read = \(exitsLiteral)

        def record(value):
            with open(transcript, "a", encoding="utf-8") as handle:
                handle.write(json.dumps(value, separators=(",", ":")) + "\\n")

        def read_exact(count):
            data = b""
            while len(data) < count:
                chunk = sys.stdin.buffer.read(count - len(data))
                if not chunk:
                    raise EOFError()
                data += chunk
            return data

        def read_frame():
            first, second = read_exact(2)
            length = second & 0x7f
            if length == 126:
                length = struct.unpack("!H", read_exact(2))[0]
            elif length == 127:
                length = struct.unpack("!Q", read_exact(8))[0]
            masked = bool(second & 0x80)
            mask = read_exact(4) if masked else b""
            payload = read_exact(length)
            if masked:
                payload = bytes(byte ^ mask[index % 4]
                                for index, byte in enumerate(payload))
            return payload, masked

        def send_frame(value):
            payload = json.dumps(value, separators=(",", ":")).encode()
            header = bytearray([0x81])
            if len(payload) < 126:
                header.append(len(payload))
            elif len(payload) <= 65535:
                header.append(126)
                header.extend(struct.pack("!H", len(payload)))
            else:
                header.append(127)
                header.extend(struct.pack("!Q", len(payload)))
            sys.stdout.buffer.write(header + payload)
            sys.stdout.buffer.flush()

        def response_for(request):
            method = request.get("method")
            request_id = request.get("id")
            if method == "initialize":
                return {"id": request_id, "result": {
                    "userAgent": "fake", "codexHome": "/tmp",
                    "platformFamily": "unix", "platformOs": "macos"
                }}
            if method == "account/rateLimits/read":
                return {"id": request_id, "result": {
                    "rateLimits": {
                        "limitId": "codex", "limitName": None,
                        "primary": {"usedPercent": 7,
                                    "windowDurationMins": 10080,
                                    "resetsAt": 1785552000},
                        "secondary": None, "credits": None,
                        "planType": "pro", "rateLimitReachedType": None
                    },
                    "rateLimitsByLimitId": None,
                    "rateLimitResetCredits": {"availableCount": 2,
                                               "credits": []}
                }}
            if method == "account/read":
                return {"id": request_id, "result": {
                    "account": {"type": "chatgpt", "email": "fake@example.com",
                                "planType": "pro"},
                    "requiresOpenaiAuth": False
                }}
            return None

        args = sys.argv[1:]
        record({"args": args})
        if "proxy" in args:
            header = b""
            while b"\\r\\n\\r\\n" not in header:
                header += read_exact(1)
            if not managed_handshake_succeeds:
                sys.stdout.buffer.write(b"HTTP/1.1 403 Forbidden\\r\\n\\r\\n")
                sys.stdout.buffer.flush()
                sys.exit(0)
            key = None
            for line in header.decode().split("\\r\\n"):
                if line.lower().startswith("sec-websocket-key:"):
                    key = line.split(":", 1)[1].strip()
            accept = base64.b64encode(hashlib.sha1(
                (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()
            ).digest()).decode()
            sys.stdout.buffer.write((
                "HTTP/1.1 101 Switching Protocols\\r\\n"
                "Upgrade: websocket\\r\\n"
                "Connection: Upgrade\\r\\n"
                "Sec-WebSocket-Accept: " + accept + "\\r\\n\\r\\n"
            ).encode())
            sys.stdout.buffer.flush()
            while True:
                try:
                    payload, masked = read_frame()
                except EOFError:
                    break
                request = json.loads(payload)
                request["masked"] = masked
                record(request)
                response = response_for(request)
                if response is not None:
                    send_frame(response)
                if (managed_exits_after_account_read
                        and request.get("method") == "account/read"):
                    sys.exit(0)
        else:
            for line in sys.stdin.buffer:
                request = json.loads(line)
                record(request)
                response = response_for(request)
                if response is not None:
                    print(json.dumps(response, separators=(",", ":")), flush=True)
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        return (directory, executable, transcript)
    }

    private func transcriptRecords(at url: URL) throws -> [[String: Any]] {
        try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n")
            .map { line in
                try XCTUnwrap(
                    JSONSerialization.jsonObject(with: Data(line.utf8))
                        as? [String: Any]
                )
            }
    }

    private func serverFrame(
        payload: Data,
        opcode: UInt8 = 0x1,
        isFinal: Bool = true
    ) -> Data {
        var frame = Data([(isFinal ? 0x80 : 0) | opcode])
        if payload.count < 126 {
            frame.append(UInt8(payload.count))
        } else {
            frame.append(126)
            frame.append(UInt8((payload.count >> 8) & 0xFF))
            frame.append(UInt8(payload.count & 0xFF))
        }
        frame.append(payload)
        return frame
    }

    private func handshakeResponse(
        accept: String,
        connection: String = "Upgrade"
    ) -> Data {
        let lines = [
            "HTTP/1.1 101 Switching Protocols",
            "Upgrade: websocket",
            "Connection: \(connection)",
            "Sec-WebSocket-Accept: \(accept)",
            "",
            "",
        ]
        return Data(lines.joined(separator: "\r\n").utf8)
    }

    private func decodeClientFrame(_ frame: Data) throws -> (
        opcode: UInt8,
        payload: Data
    ) {
        let bytes = [UInt8](frame)
        XCTAssertGreaterThanOrEqual(bytes.count, 6)
        XCTAssertEqual(bytes[0] & 0x80, 0x80)
        XCTAssertEqual(bytes[1] & 0x80, 0x80)
        var cursor = 2
        var length = Int(bytes[1] & 0x7F)
        if length == 126 {
            length = Int(bytes[cursor]) << 8 | Int(bytes[cursor + 1])
            cursor += 2
        } else if length == 127 {
            length = 0
            for byte in bytes[cursor..<(cursor + 8)] {
                length = (length << 8) | Int(byte)
            }
            cursor += 8
        }
        let mask = Array(bytes[cursor..<(cursor + 4)])
        cursor += 4
        let payload = Data(
            bytes[cursor..<(cursor + length)].enumerated().map {
                $0.element ^ mask[$0.offset % 4]
            }
        )
        return (bytes[0] & 0x0F, payload)
    }
}
