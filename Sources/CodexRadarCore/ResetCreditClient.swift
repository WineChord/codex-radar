import Foundation

public struct ResetCreditClient {
    public enum ClientError: LocalizedError, Equatable {
        case authFileNotFound(String)
        case invalidAuthFile
        case accessTokenNotFound
        case unauthorized(Int)
        case httpStatus(Int)
        case emptyResponse

        public var errorDescription: String? {
            switch self {
            case .authFileNotFound(let path):
                return "Codex auth file was not found at \(path)"
            case .invalidAuthFile:
                return "Codex auth file is not valid JSON"
            case .accessTokenNotFound:
                return "Codex access token was not found in auth.json"
            case .unauthorized(let status):
                return "Reset credit request was rejected with HTTP \(status)"
            case .httpStatus(let status):
                return "Reset credit request failed with HTTP \(status)"
            case .emptyResponse:
                return "Reset credit response was empty"
            }
        }
    }

    private let authURLProvider: () -> URL
    private let session: URLSession

    public init(
        authURLProvider: @escaping () -> URL = ResetCreditClient.defaultAuthURL,
        session: URLSession = .shared
    ) {
        self.authURLProvider = authURLProvider
        self.session = session
    }

    public func fetch() async throws -> ResetCreditSnapshot {
        let token = try Self.readAccessToken(authURL: authURLProvider())
        var request = URLRequest(url: AppConstants.resetCreditsURL)
        request.timeoutInterval = TimeInterval(AppConstants.requestTimeoutSeconds)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("\(AppConstants.clientName)/\(AppConstants.appVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.emptyResponse
        }
        switch httpResponse.statusCode {
        case 200..<300:
            guard !data.isEmpty else {
                throw ClientError.emptyResponse
            }
            return try ResetCreditSnapshot(responseData: data)
        case 401, 403:
            throw ClientError.unauthorized(httpResponse.statusCode)
        default:
            throw ClientError.httpStatus(httpResponse.statusCode)
        }
    }

    public static func readAccessToken(authURL: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: authURL.path) else {
            throw ClientError.authFileNotFound(authURL.path)
        }
        let data = try Data(contentsOf: authURL)
        return try accessToken(fromAuthData: data)
    }

    public static func accessToken(fromAuthData data: Data) throws -> String {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ClientError.invalidAuthFile
        }
        guard let dictionary = object as? [String: Any] else {
            throw ClientError.invalidAuthFile
        }
        let token = stringValue(dictionary["access_token"])
            ?? stringValue(dictionary["accessToken"])
            ?? stringValue((dictionary["tokens"] as? [String: Any])?["access_token"])
            ?? stringValue((dictionary["tokens"] as? [String: Any])?["accessToken"])
        guard let token, !token.isEmpty else {
            throw ClientError.accessTokenNotFound
        }
        return token
    }

    private static func stringValue(_ value: Any?) -> String? {
        value as? String
    }

    public static func defaultAuthURL() -> URL {
        if let override = ProcessInfo.processInfo.environment[AppConstants.codexAuthPathEnvironmentKey],
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("auth.json", isDirectory: false)
    }
}
