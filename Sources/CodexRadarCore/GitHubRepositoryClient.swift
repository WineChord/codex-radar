import Foundation

public struct GitHubRepositoryStats: Equatable {
    public let stargazersCount: Int

    public init(stargazersCount: Int) {
        self.stargazersCount = stargazersCount
    }
}

public struct GitHubRepositoryClient {
    public enum ClientError: LocalizedError, Equatable {
        case invalidStatus(Int)

        public var errorDescription: String? {
            switch self {
            case .invalidStatus(let statusCode):
                if statusCode == 403 {
                    return "GitHub repository stats returned HTTP 403"
                }
                return "GitHub repository stats returned HTTP \(statusCode)"
            }
        }
    }

    private struct RepositoryPayload: Decodable {
        let stargazersCount: Int

        enum CodingKeys: String, CodingKey {
            case stargazersCount = "stargazers_count"
        }
    }

    private let url: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(
        url: URL = AppConstants.githubRepositoryAPIURL,
        session: URLSession = .shared
    ) {
        self.url = url
        self.session = session
        self.decoder = JSONDecoder()
    }

    public func fetchStats() async throws -> GitHubRepositoryStats {
        var request = URLRequest(url: url)
        request.timeoutInterval = Double(AppConstants.requestTimeoutSeconds)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("\(AppConstants.clientName)/\(AppConstants.appVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw ClientError.invalidStatus(httpResponse.statusCode)
        }
        return try Self.decodeStats(from: data, decoder: decoder)
    }

    public static func decodeStats(from data: Data, decoder: JSONDecoder = JSONDecoder()) throws -> GitHubRepositoryStats {
        let payload = try decoder.decode(RepositoryPayload.self, from: data)
        return GitHubRepositoryStats(stargazersCount: payload.stargazersCount)
    }
}
