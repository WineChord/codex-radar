import Foundation

public struct CodexRadarClient {
    public enum ClientError: LocalizedError {
        case invalidStatus(Int)

        public var errorDescription: String? {
            switch self {
            case .invalidStatus(let statusCode):
                return "CodexRadar returned HTTP \(statusCode)"
            }
        }
    }

    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(
        baseURL: URL = AppConstants.codexRadarBaseURL,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = JSONDecoder()
    }

    public func fetchCurrent() async throws -> RadarCurrent {
        try await fetchJSON(AppConstants.currentPath, as: RadarCurrent.self)
    }

    public func fetchPrediction() async throws -> RadarPrediction {
        try await fetchJSON(AppConstants.predictionPath, as: RadarPrediction.self)
    }

    public func fetchModelIQ() async throws -> ModelIQEnvelope {
        try await fetchJSON(AppConstants.modelIQPath, as: ModelIQEnvelope.self)
    }

    private func fetchJSON<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let url = baseURL.appending(path: path)
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            return try decoder.decode(T.self, from: data)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ClientError.invalidStatus(httpResponse.statusCode)
        }
        return try decoder.decode(T.self, from: data)
    }
}
