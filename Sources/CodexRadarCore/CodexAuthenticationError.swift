import Foundation

/// Recognizes sign-in failures in app-server messages, including nested HTTP bodies.
public enum CodexAuthenticationError {
    public static func matches(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return [
            "authentication required", "not logged in", "signed out",
            "authentication token has expired", "token_expired",
            "token has expired", "token is expired", "invalid access token",
            "invalid authentication token", "invalid_token",
            "refresh_token_expired", "refresh_token_reused", "refresh_token_invalid",
        ].contains { normalized.contains($0) }
    }
}
