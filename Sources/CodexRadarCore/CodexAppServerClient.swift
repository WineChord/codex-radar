import Foundation

public actor CodexAppServerClient {
    public enum ClientError: LocalizedError {
        case codexBinaryNotFound
        case processUnavailable
        case requestTimedOut
        case responseMissingResult
        case rpcError(String)

        public var errorDescription: String? {
            switch self {
            case .codexBinaryNotFound:
                return "Codex binary was not found"
            case .processUnavailable:
                return "Codex app-server is not available"
            case .requestTimedOut:
                return "Codex app-server request timed out"
            case .responseMissingResult:
                return "Codex app-server response did not contain a result"
            case .rpcError(let message):
                return message
            }
        }
    }

    private struct RPCEnvelope<T: Decodable>: Decodable {
        let id: Int?
        let result: T?
        let error: RPCError?
    }

    private struct RPCError: Decodable {
        let code: Int?
        let message: String
    }

    private let binaryURLProvider: () -> URL?
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputBuffer = Data()
    private var nextID = 1
    private var processGeneration = 0
    private var initialized = false
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]

    public init(binaryURLProvider: @escaping () -> URL? = CodexBinaryLocator.findBinary) {
        self.binaryURLProvider = binaryURLProvider
    }

    deinit {
        process?.terminate()
    }

    public func readRateLimits() async throws -> RateLimitResponse {
        try await ensureStarted()
        let data = try await sendRequest(
            method: "account/rateLimits/read",
            params: nil
        )
        return try decodeResult(data, as: RateLimitResponse.self)
    }

    public func shutdown() {
        processGeneration += 1
        process?.terminate()
        process = nil
        inputHandle = nil
        initialized = false
        failPending(ClientError.processUnavailable)
    }

    private func ensureStarted() async throws {
        if process?.isRunning == true, initialized {
            return
        }
        try startProcess()
        let params: [String: Any] = [
            "clientInfo": [
                "name": AppConstants.clientName,
                "title": AppConstants.appName,
                "version": AppConstants.appVersion,
            ],
            "capabilities": [
                "experimentalApi": false,
                "requestAttestation": false,
                "optOutNotificationMethods": [],
            ],
        ]
        let data = try await sendRequest(method: "initialize", params: params)
        let _: InitializeResult = try decodeResult(data, as: InitializeResult.self)
        initialized = true
    }

    private func startProcess() throws {
        shutdown()
        guard let binaryURL = binaryURLProvider() else {
            throw ClientError.codexBinaryNotFound
        }
        processGeneration += 1
        let generation = processGeneration

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = binaryURL
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        process.terminationHandler = { [weak self] _ in
            Task {
                await self?.handleTermination(generation: generation)
            }
        }
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            Task {
                await self?.handleOutput(data)
            }
        }
        error.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        try process.run()
        self.process = process
        self.inputHandle = input.fileHandleForWriting
    }

    private func sendRequest(method: String, params: [String: Any]?) async throws -> Data {
        guard process?.isRunning == true, let inputHandle else {
            throw ClientError.processUnavailable
        }
        let id = nextID
        nextID += 1
        var object: [String: Any] = [
            "id": id,
            "method": method,
        ]
        if let params {
            object["params"] = params
        }
        let payload = try JSONSerialization.data(withJSONObject: object)
        var line = payload
        line.append(0x0A)

        return try await withTimeout(seconds: AppConstants.requestTimeoutSeconds) {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    self.pending[id] = continuation
                    inputHandle.write(line)
                }
            } onCancel: {
                Task {
                    await self.cancelPending(id: id)
                }
            }
        }
    }

    private func handleOutput(_ data: Data) {
        outputBuffer.append(data)
        let newline = Data([0x0A])
        while let range = outputBuffer.range(of: newline) {
            let line = outputBuffer.subdata(in: outputBuffer.startIndex..<range.lowerBound)
            outputBuffer.removeSubrange(outputBuffer.startIndex..<range.upperBound)
            handleLine(line)
        }
    }

    private func handleLine(_ data: Data) {
        guard !data.isEmpty else {
            return
        }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let id = numericID(from: dictionary["id"]) else {
            return
        }
        guard let continuation = pending.removeValue(forKey: id) else {
            return
        }
        continuation.resume(returning: data)
    }

    private func handleTermination(generation: Int) {
        guard generation == processGeneration else {
            return
        }
        process = nil
        inputHandle = nil
        initialized = false
        failPending(ClientError.processUnavailable)
    }

    private func cancelPending(id: Int) {
        pending.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }

    private func failPending(_ error: Error) {
        let continuations = pending.values
        pending.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
    }

    private func decodeResult<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        let envelope = try JSONDecoder().decode(RPCEnvelope<T>.self, from: data)
        if let error = envelope.error {
            throw ClientError.rpcError(error.message)
        }
        guard let result = envelope.result else {
            throw ClientError.responseMissingResult
        }
        return result
    }

    private func numericID(from value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }
        if let doubleValue = value as? Double {
            return Int(doubleValue)
        }
        if let stringValue = value as? String {
            return Int(stringValue)
        }
        return nil
    }

    private func withTimeout<T>(
        seconds: UInt64,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw ClientError.requestTimedOut
            }
            guard let value = try await group.next() else {
                throw ClientError.requestTimedOut
            }
            group.cancelAll()
            return value
        }
    }
}

private struct InitializeResult: Decodable {
    let userAgent: String
    let codexHome: String
    let platformFamily: String
    let platformOs: String
}

public enum CodexBinaryLocator {
    public static func findBinary() -> URL? {
        findBinary(
            environment: ProcessInfo.processInfo.environment,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    static func findBinary(
        environment: [String: String],
        homeDirectory: URL,
        systemCandidates: [String] = defaultSystemCandidatePaths,
        fileManager: FileManager = .default
    ) -> URL? {
        if let override = environment[AppConstants.codexPathEnvironmentKey],
           fileManager.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }
        let candidates = candidatePaths(
            environment: environment,
            homeDirectory: homeDirectory,
            systemCandidates: systemCandidates
        )
        if let path = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    static func candidatePaths(
        environment: [String: String],
        homeDirectory: URL,
        systemCandidates: [String] = defaultSystemCandidatePaths
    ) -> [String] {
        let homeCandidates = [
            homeDirectory
                .appendingPathComponent(".codex/packages/standalone/current/bin/codex")
                .path,
            homeDirectory
                .appendingPathComponent(".codex/packages/standalone/current/codex")
                .path,
            homeDirectory
                .appendingPathComponent(".local/bin/codex")
                .path,
        ]
        let pathCandidates = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0).appendingPathComponent("codex").path }
        return homeCandidates + pathCandidates + systemCandidates
    }

    private static let defaultSystemCandidatePaths = [
        AppConstants.codexAppBinaryPath,
        AppConstants.chatGPTAppBinaryPath,
    ]
}
