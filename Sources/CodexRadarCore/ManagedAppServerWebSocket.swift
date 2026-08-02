import CryptoKit
import Darwin
import Foundation

enum ManagedAppServerTransportError: LocalizedError, Equatable {
    case handshakeTooLarge
    case invalidHandshake
    case invalidFrame
    case messageTooLarge

    var errorDescription: String? {
        switch self {
        case .handshakeTooLarge, .invalidHandshake:
            return "The managed Codex app-server handshake was invalid"
        case .invalidFrame:
            return "The managed Codex app-server sent an invalid message"
        case .messageTooLarge:
            return "The managed Codex app-server message was too large"
        }
    }
}

struct ManagedAppServerHandshake {
    private static let headerTerminator = Data("\r\n\r\n".utf8)
    private static let maximumHeaderBytes = 64 * 1_024
    private static let webSocketGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    let key: String
    let expectedAccept: String

    init(key: String = Self.randomKey()) {
        self.key = key
        expectedAccept = Self.acceptValue(for: key)
    }

    var request: Data {
        let lines = [
            "GET / HTTP/1.1",
            "Host: localhost",
            "Connection: Upgrade",
            "Upgrade: websocket",
            "Sec-WebSocket-Key: \(key)",
            "Sec-WebSocket-Version: 13",
            "",
            "",
        ]
        return Data(lines.joined(separator: "\r\n").utf8)
    }

    func consumeResponse(from buffer: inout Data) throws -> Bool {
        guard let terminator = buffer.range(of: Self.headerTerminator) else {
            if buffer.count > Self.maximumHeaderBytes {
                throw ManagedAppServerTransportError.handshakeTooLarge
            }
            return false
        }
        let headerData = buffer.subdata(
            in: buffer.startIndex..<terminator.upperBound
        )
        buffer.removeSubrange(buffer.startIndex..<terminator.upperBound)
        guard let header = String(data: headerData, encoding: .utf8) else {
            throw ManagedAppServerTransportError.invalidHandshake
        }
        let lines = header.components(separatedBy: "\r\n")
        guard lines.first?.hasPrefix("HTTP/1.1 101 ") == true else {
            throw ManagedAppServerTransportError.invalidHandshake
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let separator = line.firstIndex(of: ":") else {
                throw ManagedAppServerTransportError.invalidHandshake
            }
            let name = line[..<separator]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let previous = headers[name] {
                headers[name] = "\(previous),\(value)"
            } else {
                headers[name] = value
            }
        }
        let connectionTokens = headers["connection"]?
            .split(separator: ",")
            .map {
                $0.trimmingCharacters(in: CharacterSet.whitespaces)
                    .lowercased()
            } ?? []
        guard headers["upgrade"]?.lowercased() == "websocket",
              connectionTokens.contains("upgrade"),
              headers["sec-websocket-accept"] == expectedAccept else {
            throw ManagedAppServerTransportError.invalidHandshake
        }
        return true
    }

    static func acceptValue(for key: String) -> String {
        let digest = Insecure.SHA1.hash(
            data: Data((key + webSocketGUID).utf8)
        )
        return Data(digest).base64EncodedString()
    }

    private static func randomKey() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<16).map { _ in
            UInt8.random(in: .min ... .max, using: &generator)
        }
        return Data(bytes).base64EncodedString()
    }
}

struct ManagedAppServerWebSocketCodec {
    enum Event: Equatable {
        case text(Data)
        case ping(Data)
        case close
    }

    private static let maximumMessageBytes = 8 * 1_024 * 1_024
    private var buffer = Data()
    private var fragmentedText = Data()
    private var receivesContinuation = false

    mutating func append(_ data: Data) throws -> [Event] {
        buffer.append(data)
        var events: [Event] = []
        while let frame = try nextFrame() {
            switch frame.opcode {
            case 0x0:
                guard receivesContinuation else {
                    throw ManagedAppServerTransportError.invalidFrame
                }
                try appendFragment(frame.payload)
                if frame.isFinal {
                    events.append(.text(fragmentedText))
                    fragmentedText.removeAll(keepingCapacity: false)
                    receivesContinuation = false
                }
            case 0x1:
                guard !receivesContinuation else {
                    throw ManagedAppServerTransportError.invalidFrame
                }
                if frame.isFinal {
                    events.append(.text(frame.payload))
                } else {
                    receivesContinuation = true
                    fragmentedText = frame.payload
                    try validateMessageSize(fragmentedText.count)
                }
            case 0x8:
                guard frame.isFinal, frame.payload.count <= 125 else {
                    throw ManagedAppServerTransportError.invalidFrame
                }
                events.append(.close)
            case 0x9:
                guard frame.isFinal, frame.payload.count <= 125 else {
                    throw ManagedAppServerTransportError.invalidFrame
                }
                events.append(.ping(frame.payload))
            case 0xA:
                guard frame.isFinal, frame.payload.count <= 125 else {
                    throw ManagedAppServerTransportError.invalidFrame
                }
            default:
                throw ManagedAppServerTransportError.invalidFrame
            }
        }
        return events
    }

    static func clientFrame(
        payload: Data,
        opcode: UInt8 = 0x1,
        mask: [UInt8]? = nil
    ) -> Data {
        precondition(opcode <= 0xF)
        let mask = mask ?? randomMask()
        precondition(mask.count == 4)
        var frame = Data([0x80 | opcode])
        switch payload.count {
        case 0..<126:
            frame.append(0x80 | UInt8(payload.count))
        case 126...65_535:
            frame.append(0x80 | 126)
            frame.append(UInt8((payload.count >> 8) & 0xFF))
            frame.append(UInt8(payload.count & 0xFF))
        default:
            frame.append(0x80 | 127)
            let length = UInt64(payload.count).bigEndian
            withUnsafeBytes(of: length) { frame.append(contentsOf: $0) }
        }
        frame.append(contentsOf: mask)
        for (index, byte) in payload.enumerated() {
            frame.append(byte ^ mask[index % mask.count])
        }
        return frame
    }

    private mutating func nextFrame() throws -> (
        isFinal: Bool,
        opcode: UInt8,
        payload: Data
    )? {
        guard buffer.count >= 2 else {
            return nil
        }
        let bytes = [UInt8](buffer)
        let first = bytes[0]
        let second = bytes[1]
        guard first & 0x70 == 0, second & 0x80 == 0 else {
            throw ManagedAppServerTransportError.invalidFrame
        }
        var cursor = 2
        var length = UInt64(second & 0x7F)
        if length == 126 {
            guard bytes.count >= cursor + 2 else {
                return nil
            }
            length = UInt64(bytes[cursor]) << 8
                | UInt64(bytes[cursor + 1])
            cursor += 2
        } else if length == 127 {
            guard bytes.count >= cursor + 8 else {
                return nil
            }
            guard bytes[cursor] & 0x80 == 0 else {
                throw ManagedAppServerTransportError.invalidFrame
            }
            length = 0
            for byte in bytes[cursor..<(cursor + 8)] {
                length = (length << 8) | UInt64(byte)
            }
            cursor += 8
        }
        guard length <= UInt64(Self.maximumMessageBytes),
              length <= UInt64(Int.max) else {
            throw ManagedAppServerTransportError.messageTooLarge
        }
        let payloadLength = Int(length)
        guard bytes.count >= cursor + payloadLength else {
            return nil
        }
        let payload = Data(bytes[cursor..<(cursor + payloadLength)])
        buffer.removeSubrange(
            buffer.startIndex..<buffer.index(
                buffer.startIndex,
                offsetBy: cursor + payloadLength
            )
        )
        return (
            isFinal: first & 0x80 != 0,
            opcode: first & 0x0F,
            payload: payload
        )
    }

    private mutating func appendFragment(_ data: Data) throws {
        try validateMessageSize(fragmentedText.count + data.count)
        fragmentedText.append(data)
    }

    private func validateMessageSize(_ size: Int) throws {
        guard size <= Self.maximumMessageBytes else {
            throw ManagedAppServerTransportError.messageTooLarge
        }
    }

    private static func randomMask() -> [UInt8] {
        var generator = SystemRandomNumberGenerator()
        return (0..<4).map { _ in
            UInt8.random(in: .min ... .max, using: &generator)
        }
    }
}

public enum CodexManagedAppServerLocator {
    public static func findControlSocket() -> URL? {
        findControlSocket(
            environment: ProcessInfo.processInfo.environment,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    static func findControlSocket(
        environment: [String: String],
        homeDirectory: URL,
        fileManager: FileManager = .default,
        userID: uid_t = getuid()
    ) -> URL? {
        let codexHome: URL
        if let override = environment["CODEX_HOME"],
           override.hasPrefix("/") {
            codexHome = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            codexHome = homeDirectory.appendingPathComponent(
                ".codex",
                isDirectory: true
            )
        }
        let socket = codexHome
            .appendingPathComponent("app-server-control", isDirectory: true)
            .appendingPathComponent("app-server-control.sock")
        guard let attributes = try? fileManager.attributesOfItem(
            atPath: socket.path
        ), attributes[.type] as? FileAttributeType == .typeSocket,
              let owner = numericAttribute(attributes[.ownerAccountID]),
              owner == UInt64(userID),
              let permissions = numericAttribute(attributes[.posixPermissions]),
              (permissions & 0o077) == 0 else {
            return nil
        }
        return socket
    }

    private static func numericAttribute(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber {
            return number.uint64Value
        }
        if let integer = value as? Int {
            return UInt64(exactly: integer)
        }
        return nil
    }
}
