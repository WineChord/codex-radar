import Darwin
import Foundation

public actor CodexAppServerClient: ResetCreditProtectionAppServerServing {
    private enum ProcessTransport: Equatable {
        case standaloneStdio
        case managedWebSocket
    }

    public enum ClientError: LocalizedError {
        case codexBinaryNotFound
        case processUnavailable
        case requestTimedOut
        case requestCancelledBeforeDispatch
        case resetCreditSessionUnavailableBeforeDispatch
        case resetCreditDispatchNotAuthorized
        case resetCreditDispatchAuthorizationUnavailable
        case responseMissingResult
        case invalidRequest(String)
        case rpcError(code: Int?, message: String)

        public var errorDescription: String? {
            switch self {
            case .codexBinaryNotFound:
                return "Codex binary was not found"
            case .processUnavailable:
                return "Codex app-server is not available"
            case .requestTimedOut:
                return "Codex app-server request timed out"
            case .requestCancelledBeforeDispatch:
                return "The reset-credit request was cancelled before dispatch"
            case .resetCreditSessionUnavailableBeforeDispatch:
                return "The verified Codex app-server session ended before dispatch"
            case .resetCreditDispatchNotAuthorized:
                return "Reset-credit auto-use was disabled before dispatch"
            case .resetCreditDispatchAuthorizationUnavailable:
                return "Reset-credit dispatch authorization could not be verified"
            case .responseMissingResult:
                return "Codex app-server response did not contain a result"
            case .invalidRequest(let message):
                return message
            case .rpcError(_, let message):
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
    private let managedControlSocketURLProvider: () -> URL?
    private let allowsAutomaticRestart: Bool
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var errorHandle: FileHandle?
    private var outputBuffer = Data()
    private var transport: ProcessTransport?
    private var managedHandshake: ManagedAppServerHandshake?
    private var managedHandshakeContinuation: CheckedContinuation<Void, Error>?
    private var managedWebSocketCodec = ManagedAppServerWebSocketCodec()
    private var nextID = 1
    private var processGeneration = 0
    private var initialized = false
    private var hasStartedProcess = false
    private var hasCompletedRead = false
    private var hasCompletedReadOnCurrentProcess = false
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]

    public init(
        allowsAutomaticRestart: Bool = true
    ) {
        binaryURLProvider = CodexBinaryLocator.findBinary
        managedControlSocketURLProvider =
            CodexManagedAppServerLocator.findControlSocket
        self.allowsAutomaticRestart = allowsAutomaticRestart
    }

    public init(
        binaryURLProvider: @escaping () -> URL?,
        allowsAutomaticRestart: Bool = true,
        managedControlSocketURLProvider: @escaping () -> URL? = { nil }
    ) {
        self.binaryURLProvider = binaryURLProvider
        self.managedControlSocketURLProvider =
            managedControlSocketURLProvider
        self.allowsAutomaticRestart = allowsAutomaticRestart
    }

    deinit {
        process?.terminationHandler = nil
        outputHandle?.readabilityHandler = nil
        errorHandle?.readabilityHandler = nil
        process?.terminate()
    }

    public func readRateLimits() async throws -> RateLimitResponse {
        let result: RateLimitResponse = try await performRead(
            method: "account/rateLimits/read",
            params: nil
        )
        hasCompletedRead = true
        hasCompletedReadOnCurrentProcess = process?.isRunning == true
            && initialized
        return result
    }

    public func readAccount() async throws -> CodexAccountResponse {
        let result: CodexAccountResponse = try await performRead(
            method: "account/read",
            params: ["refreshToken": false]
        )
        hasCompletedRead = true
        hasCompletedReadOnCurrentProcess = process?.isRunning == true
            && initialized
        return result
    }

    public func consumeResetCredit(
        creditID: String,
        idempotencyKey: String,
        authorization: ResetCreditProtectionDispatchAuthorization
    ) async throws -> ResetCreditConsumeResponse {
        guard !creditID.isEmpty else {
            throw ClientError.invalidRequest("Reset credit ID must not be empty")
        }
        guard !idempotencyKey.isEmpty else {
            throw ClientError.invalidRequest("Reset credit idempotency key must not be empty")
        }
        guard process?.isRunning == true, initialized else {
            throw ClientError.resetCreditSessionUnavailableBeforeDispatch
        }
        let data = try await sendRequest(
            method: "account/rateLimitResetCredit/consume",
            params: [
                "idempotencyKey": idempotencyKey,
                "creditId": creditID,
            ],
            dispatchAuthorization: authorization,
            authorizedCreditID: creditID
        )
        return try decodeResult(data, as: ResetCreditConsumeResponse.self)
    }

    public func shutdown() {
        let hasResources = process != nil
            || inputHandle != nil
            || outputHandle != nil
            || errorHandle != nil
            || initialized
            || !outputBuffer.isEmpty
            || !pending.isEmpty
        guard hasResources else {
            return
        }

        processGeneration += 1
        let process = self.process
        let inputHandle = self.inputHandle
        let outputHandle = self.outputHandle
        let errorHandle = self.errorHandle

        process?.terminationHandler = nil
        outputHandle?.readabilityHandler = nil
        errorHandle?.readabilityHandler = nil
        self.process = nil
        self.inputHandle = nil
        self.outputHandle = nil
        self.errorHandle = nil
        transport = nil
        managedHandshake = nil
        managedWebSocketCodec = ManagedAppServerWebSocketCodec()
        initialized = false
        hasCompletedReadOnCurrentProcess = false
        outputBuffer.removeAll(keepingCapacity: false)
        managedHandshakeContinuation?.resume(
            throwing: ClientError.processUnavailable
        )
        managedHandshakeContinuation = nil
        failPending(ClientError.processUnavailable)

        if process?.isRunning == true {
            process?.terminate()
        }
        try? inputHandle?.close()
        try? outputHandle?.close()
        try? errorHandle?.close()
    }

    func hasLiveInitializedSession() -> Bool {
        process?.isRunning == true && initialized
    }

    private func ensureStarted() async throws {
        if process?.isRunning == true, initialized {
            return
        }
        guard allowsAutomaticRestart || !hasStartedProcess else {
            throw ClientError.processUnavailable
        }
        if let socketURL = managedControlSocketURLProvider() {
            do {
                try await startAndInitialize(
                    transport: .managedWebSocket,
                    socketURL: socketURL
                )
                return
            } catch {
                shutdown()
            }
        }
        try await startAndInitialize(
            transport: .standaloneStdio,
            socketURL: nil
        )
    }

    private func startAndInitialize(
        transport: ProcessTransport,
        socketURL: URL?
    ) async throws {
        try startProcess(transport: transport, socketURL: socketURL)
        if transport == .managedWebSocket {
            try await performManagedHandshake()
        }
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
        if transport == .managedWebSocket {
            try sendNotification(method: "initialized")
        }
        initialized = true
    }

    private func startProcess(
        transport: ProcessTransport,
        socketURL: URL?
    ) throws {
        shutdown()
        guard let binaryURL = binaryURLProvider() else {
            throw ClientError.codexBinaryNotFound
        }
        processGeneration += 1
        let generation = processGeneration

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let standardError = Pipe()
        guard fcntl(
            input.fileHandleForWriting.fileDescriptor,
            F_SETNOSIGPIPE,
            1
        ) != -1 else {
            throw ClientError.processUnavailable
        }
        process.executableURL = binaryURL
        switch transport {
        case .standaloneStdio:
            process.arguments = ["app-server", "--listen", "stdio://"]
        case .managedWebSocket:
            guard let socketURL else {
                throw ClientError.processUnavailable
            }
            process.arguments = [
                "app-server",
                "proxy",
                "--sock",
                socketURL.path,
            ]
        }
        process.standardInput = input
        process.standardOutput = output
        process.standardError = standardError
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
                await self?.handleOutput(data, generation: generation)
            }
        }
        standardError.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            output.fileHandleForReading.readabilityHandler = nil
            standardError.fileHandleForReading.readabilityHandler = nil
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
            try? standardError.fileHandleForReading.close()
            throw error
        }
        hasStartedProcess = true
        self.transport = transport
        self.process = process
        self.inputHandle = input.fileHandleForWriting
        self.outputHandle = output.fileHandleForReading
        self.errorHandle = standardError.fileHandleForReading
    }

    private func performManagedHandshake() async throws {
        guard transport == .managedWebSocket,
              process?.isRunning == true,
              inputHandle != nil else {
            throw ClientError.processUnavailable
        }
        let handshake = ManagedAppServerHandshake()
        managedHandshake = handshake
        try await withTimeout(seconds: AppConstants.requestTimeoutSeconds) {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    self.managedHandshakeContinuation = continuation
                    do {
                        try self.writeToInput(handshake.request)
                    } catch {
                        self.managedHandshakeContinuation = nil
                        continuation.resume(throwing: error)
                        self.shutdown()
                    }
                }
            } onCancel: {
                Task {
                    await self.cancelManagedHandshake()
                }
            }
        }
    }

    private func performRead<T: Decodable>(
        method: String,
        params: [String: Any]?
    ) async throws -> T {
        try await ensureStarted()
        let usedManagedTransport = transport == .managedWebSocket
        do {
            let data = try await sendRequest(method: method, params: params)
            return try decodeResult(data, as: T.self)
        } catch {
            let isFallbackError = shouldFallbackFromManagedTransport(error)
            let fallbackIsSafe = allowsAutomaticRestart
                ? !hasCompletedReadOnCurrentProcess
                : !hasCompletedRead
            guard usedManagedTransport,
                  isFallbackError,
                  fallbackIsSafe,
                  !(error is CancellationError) else {
                if usedManagedTransport, isFallbackError {
                    shutdown()
                }
                throw error
            }
            shutdown()
            try await startAndInitialize(
                transport: .standaloneStdio,
                socketURL: nil
            )
            let data = try await sendRequest(method: method, params: params)
            return try decodeResult(data, as: T.self)
        }
    }

    private func shouldFallbackFromManagedTransport(_ error: Error) -> Bool {
        if error is ManagedAppServerTransportError {
            return true
        }
        guard let clientError = error as? ClientError else {
            return false
        }
        switch clientError {
        case .processUnavailable, .requestTimedOut:
            return true
        case .rpcError(_, let message):
            return message.localizedCaseInsensitiveContains("authentication")
                || message.localizedCaseInsensitiveContains("not logged in")
        default:
            return false
        }
    }

    private func sendRequest(
        method: String,
        params: [String: Any]?,
        dispatchAuthorization: ResetCreditProtectionDispatchAuthorization? = nil,
        authorizedCreditID: String? = nil
    ) async throws -> Data {
        guard process?.isRunning == true, inputHandle != nil else {
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
        let wirePayload: Data
        if transport == .managedWebSocket {
            wirePayload = ManagedAppServerWebSocketCodec.clientFrame(
                payload: payload
            )
        } else {
            var line = payload
            line.append(0x0A)
            wirePayload = line
        }

        return try await withTimeout(seconds: AppConstants.requestTimeoutSeconds) {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    guard !Task.isCancelled else {
                        continuation.resume(
                            throwing: ClientError.requestCancelledBeforeDispatch
                        )
                        return
                    }
                    self.pending[id] = continuation
                    do {
                        if let dispatchAuthorization, let authorizedCreditID {
                            try dispatchAuthorization.perform(
                                creditID: authorizedCreditID
                            ) {
                                guard !Task.isCancelled else {
                                    throw ClientError.requestCancelledBeforeDispatch
                                }
                                try self.writeToInput(wirePayload)
                            }
                        } else if dispatchAuthorization != nil {
                            throw ClientError.resetCreditDispatchNotAuthorized
                        } else {
                            guard !Task.isCancelled else {
                                throw ClientError.requestCancelledBeforeDispatch
                            }
                            try self.writeToInput(wirePayload)
                        }
                    } catch {
                        self.pending.removeValue(forKey: id)
                        let requestError: Error
                        switch error {
                        case ResetCreditProtectionStorageError.authorizationRevoked:
                            requestError = ClientError
                                .resetCreditDispatchNotAuthorized
                        case ResetCreditProtectionStorageError.authorizationUnavailable:
                            requestError = ClientError
                                .resetCreditDispatchAuthorizationUnavailable
                        default:
                            requestError = error
                        }
                        if let clientError = requestError as? ClientError,
                           case .processUnavailable = clientError {
                            self.shutdown()
                        }
                        continuation.resume(throwing: requestError)
                    }
                }
            } onCancel: {
                Task {
                    await self.cancelPending(id: id)
                }
            }
        }
    }

    private func handleOutput(_ data: Data, generation: Int) {
        guard generation == processGeneration else {
            return
        }
        guard transport == .managedWebSocket else {
            handleStdioOutput(data)
            return
        }
        handleManagedOutput(data)
    }

    private func handleStdioOutput(_ data: Data) {
        outputBuffer.append(data)
        let newline = Data([0x0A])
        while let range = outputBuffer.range(of: newline) {
            let line = outputBuffer.subdata(in: outputBuffer.startIndex..<range.lowerBound)
            outputBuffer.removeSubrange(outputBuffer.startIndex..<range.upperBound)
            handleLine(line)
        }
    }

    private func handleManagedOutput(_ data: Data) {
        var frameData = data
        if let handshake = managedHandshake {
            outputBuffer.append(data)
            do {
                guard try handshake.consumeResponse(from: &outputBuffer) else {
                    return
                }
            } catch {
                failManagedTransport(error)
                return
            }
            managedHandshake = nil
            frameData = outputBuffer
            outputBuffer.removeAll(keepingCapacity: false)
            managedHandshakeContinuation?.resume()
            managedHandshakeContinuation = nil
        }
        guard !frameData.isEmpty else {
            return
        }
        do {
            let events = try managedWebSocketCodec.append(frameData)
            for event in events {
                switch event {
                case .text(let payload):
                    handleLine(payload)
                case .ping(let payload):
                    do {
                        try writeToInput(
                            ManagedAppServerWebSocketCodec.clientFrame(
                                payload: payload,
                                opcode: 0xA
                            )
                        )
                    } catch {
                        failManagedTransport(error)
                        return
                    }
                case .close:
                    failManagedTransport(ClientError.processUnavailable)
                    return
                }
            }
        } catch {
            failManagedTransport(error)
        }
    }

    private func sendNotification(method: String) throws {
        guard transport == .managedWebSocket,
              process?.isRunning == true,
              inputHandle != nil else {
            throw ClientError.processUnavailable
        }
        let payload = try JSONSerialization.data(
            withJSONObject: ["method": method]
        )
        do {
            try writeToInput(
                ManagedAppServerWebSocketCodec.clientFrame(payload: payload)
            )
        } catch {
            shutdown()
            throw error
        }
    }

    private func writeToInput(_ data: Data) throws {
        guard process?.isRunning == true, let inputHandle else {
            throw ClientError.processUnavailable
        }
        do {
            try inputHandle.write(contentsOf: data)
        } catch {
            throw ClientError.processUnavailable
        }
    }

    private func failManagedTransport(_ error: Error) {
        managedHandshakeContinuation?.resume(throwing: error)
        managedHandshakeContinuation = nil
        managedHandshake = nil
        failPending(error)
        shutdown()
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
        shutdown()
    }

    private func cancelPending(id: Int) {
        pending.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }

    private func cancelManagedHandshake() {
        managedHandshakeContinuation?.resume(throwing: CancellationError())
        managedHandshakeContinuation = nil
        managedHandshake = nil
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
            throw ClientError.rpcError(code: error.code, message: error.message)
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

public struct ResetCreditConsumeResponse: Decodable, Equatable {
    public let outcome: ResetCreditConsumeOutcome
}

public enum ResetCreditConsumeOutcome: String, Codable, CaseIterable, Equatable {
    case reset
    case alreadyRedeemed
    case nothingToReset
    case noCredit
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
