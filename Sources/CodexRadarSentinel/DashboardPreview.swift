import CodexRadarCore
import Foundation

enum DashboardPreview: String, CaseIterable, Identifiable {
    case live
    case speedWindow
    case resetConfirmed
    case blocked

    var id: String {
        rawValue
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .live:
            return "Live"
        case .speedWindow:
            return language.text("速蹬", "Speed")
        case .resetConfirmed:
            return language.text("Reset", "Reset")
        case .blocked:
            return language.text("限额", "Limit")
        }
    }
}

enum DashboardPreviewFactory {
    static func state(for preview: DashboardPreview, live: DashboardState) -> DashboardState {
        switch preview {
        case .live:
            return live
        case .speedWindow:
            return speedWindowState(from: live)
        case .resetConfirmed:
            return resetConfirmedState(from: live)
        case .blocked:
            return blockedState(from: live)
        }
    }

    private static func speedWindowState(from live: DashboardState) -> DashboardState {
        var state = live
        applyFallbackMetrics(to: &state)
        state.current = decode("""
        {
          "checked_at": "2026-06-04T18:00:00+08:00",
          "status": "open",
          "window_open": true,
          "recommended_action": "speed_window_open",
          "last_window": {
            "id": "debug-speed-window",
            "title": "Preview: Codex 速蹬窗口开启",
            "status": "open",
            "opened_at": "2026-06-04T18:00:00+08:00",
            "window_minutes": 45,
            "window_human": "45 min",
            "scope": "debug preview",
            "summary": "This local preview shows the urgent visual state without sending notifications."
          },
          "prediction": {
            "level": "high",
            "probability_24h": 0.88,
            "probability_48h": 0.92,
            "should_notify": true
          }
        }
        """)
        state.prediction = decode("""
        {
          "level": "high",
          "probability_24h": 0.88,
          "probability_48h": 0.92,
          "should_notify": true,
          "reasoning_summary": "Preview mode: an active speed window should be visually urgent.",
          "updated_at": "2026-06-04T18:00:00+08:00"
        }
        """)
        return state
    }

    private static func resetConfirmedState(from live: DashboardState) -> DashboardState {
        var state = live
        applyFallbackMetrics(to: &state)
        state.current = decode("""
        {
          "checked_at": "2026-06-04T18:20:00+08:00",
          "status": "none",
          "window_open": false,
          "recommended_action": "wait",
          "last_window": {
            "id": "debug-reset-window",
            "title": "Preview: Codex limit 已确认 reset",
            "status": "closed",
            "opened_at": "2026-06-04T18:00:00+08:00",
            "closed_at": "2026-06-04T18:20:00+08:00",
            "window_minutes": 20,
            "window_human": "20 min",
            "scope": "debug preview",
            "summary": "This local preview shows the confirmed reset state."
          },
          "prediction": {
            "level": "low",
            "probability_24h": 0.08,
            "probability_48h": 0.14,
            "should_notify": false
          }
        }
        """)
        state.prediction = decode("""
        {
          "level": "low",
          "probability_24h": 0.08,
          "probability_48h": 0.14,
          "should_notify": false,
          "reasoning_summary": "Preview mode: the reset window is closed and no urgent action is active.",
          "updated_at": "2026-06-04T18:20:00+08:00"
        }
        """)
        return state
    }

    private static func blockedState(from live: DashboardState) -> DashboardState {
        var state = live
        applyFallbackMetrics(to: &state)
        state.rateLimits = decodeRateLimits("""
        {
          "rateLimits": {
            "limitId": "codex",
            "limitName": null,
            "primary": { "usedPercent": 100, "windowDurationMins": 300, "resetsAt": 1780571944 },
            "secondary": { "usedPercent": 100, "windowDurationMins": 10080, "resetsAt": 1781140743 },
            "credits": null,
            "planType": "pro",
            "rateLimitReachedType": "primary"
          },
          "rateLimitsByLimitId": null
        }
        """)
        return state
    }

    private static func applyFallbackMetrics(to state: inout DashboardState) {
        if state.rateLimits == nil {
            state.rateLimits = decodeRateLimits("""
            {
              "rateLimits": {
                "limitId": "codex",
                "limitName": null,
                "primary": { "usedPercent": 14, "windowDurationMins": 300, "resetsAt": 1780571944 },
                "secondary": { "usedPercent": 3, "windowDurationMins": 10080, "resetsAt": 1781140743 },
                "credits": null,
                "planType": "pro",
                "rateLimitReachedType": null
              },
              "rateLimitsByLimitId": null
            }
            """)
        }
        if state.modelIQ == nil {
            state.modelIQ = decode("""
            {
              "updated_at": "2026-06-04T18:00:00+08:00",
              "latest": {
                "date": "2026-06-04",
                "tasks": 12,
                "passed": 6,
                "iq_score": 75,
                "status": "red"
              }
            }
            """)
        }
    }

    private static func decode<T: Decodable>(_ json: String) -> T? {
        try? JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private static func decodeRateLimits(_ json: String) -> RateLimitDashboard? {
        guard let response: RateLimitResponse = decode(json) else {
            return nil
        }
        return RateLimitDashboard(response: response)
    }
}
