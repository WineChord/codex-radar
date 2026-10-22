import CodexRadarCore
import SwiftUI

struct QuotaDepletionForecastView: View {
    let timeline: QuotaHistoryTimeline
    let current: QuotaHistorySample?
    let language: AppLanguage
    let metrics: DashboardTextSize.Metrics

    @Binding var isExpanded: Bool

    private var forecasts: [QuotaDepletionForecast] {
        guard let current else { return [] }
        return QuotaDepletionForecast.estimates(timeline: timeline, current: current)
    }

    private func preferred(in forecasts: [QuotaDepletionForecast]) -> QuotaDepletionForecast? {
        let order: [QuotaDepletionForecast.Window] = [.hour1, .minutes30, .hours2, .hours5]
        return order.compactMap { window in
            forecasts.first { $0.window == window && $0.outcome != .insufficientData }
        }.first
    }

    var body: some View {
        let estimates = forecasts
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(text("参考时段", "Lookback"))
                        .frame(width: metrics.label * 5.5, alignment: .leading)
                    Text(text("消耗/h", "Use / h"))
                        .frame(width: metrics.label * 3.3, alignment: .trailing)
                    Spacer(minLength: 0)
                    Text(text("预计用尽 · 剩余", "Empty at · time left"))
                }
                .font(.system(size: metrics.caption))
                .foregroundStyle(.secondary)

                ForEach(QuotaDepletionForecast.Window.allCases) { window in
                    let forecast = estimates.first { $0.window == window }
                    HStack(spacing: 8) {
                        Text(windowLabel(window))
                            .frame(width: metrics.label * 5.5, alignment: .leading)
                        Text(rateLabel(forecast?.hourlyConsumption))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: metrics.label * 3.3, alignment: .trailing)
                        Spacer(minLength: 0)
                        resultLabel(forecast)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .font(.system(size: metrics.label))
                    .accessibilityElement(children: .combine)
                }

                Text(text(
                    "按相同速率估算；重置后重新计算。",
                    "Assumes unchanged usage; restarts after a reset."
                ))
                .font(.system(size: metrics.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "hourglass")
                    .foregroundStyle(.blue)
                Text(text("用尽时间预估", "Time until empty"))
                    .font(.system(size: metrics.section, weight: .semibold))
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(summary(estimates))
                        .font(.system(size: metrics.caption, weight: .medium))
                    if !isExpanded, let preferred = preferred(in: estimates) {
                        if case .depletes(let date) = preferred.outcome {
                            Text("\(durationLabel(until: date)) · \(windowLabel(preferred.window))")
                                .font(.system(size: metrics.caption))
                        } else {
                            Text(windowLabel(preferred.window))
                                .font(.system(size: metrics.caption))
                        }
                    }
                }
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
            }
        }
        .padding(10)
        .background(Color.blue.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
    }

    private func summary(_ forecasts: [QuotaDepletionForecast]) -> String {
        guard let preferred = preferred(in: forecasts) else {
            return text(current == nil ? "暂无法估算" : "记录不足", current == nil ? "Unavailable" : "Gathering history")
        }
        return outcomeLabel(preferred.outcome)
    }

    private func resultLabel(_ forecast: QuotaDepletionForecast?) -> Text {
        let outcome = Text(outcomeLabel(forecast?.outcome)).fontWeight(.medium)
        if let forecast, case .depletes(let date) = forecast.outcome {
            return outcome + Text(" · \(durationLabel(until: date))").foregroundColor(.secondary)
        }
        return outcome
    }

    private func outcomeLabel(_ outcome: QuotaDepletionForecast.Outcome?) -> String {
        switch outcome {
        case .depletes(let date):
            guard let current else { return "—" }
            let calendar = Calendar.current
            let time = date.formatted(.dateTime.hour().minute().locale(language == .zhHans ? Locale(identifier: "zh_CN") : Locale(identifier: "en_GB")))
            if calendar.isDate(date, inSameDayAs: current.timestamp) {
                return text("今天 \(time)", "Today \(time)")
            }
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: current.timestamp),
               calendar.isDate(date, inSameDayAs: tomorrow) {
                return text("明天 \(time)", "Tomorrow \(time)")
            }
            return date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute().locale(language == .zhHans ? Locale(identifier: "zh_CN") : Locale(identifier: "en_GB")))
        case .noConsumption: return text("近期未消耗", "No recent usage")
        case .alreadyDepleted: return text("已用尽", "Already empty")
        case .resetsFirst: return text("重置前用不完", "Reset comes first")
        case .slowConsumption: return text("消耗很低", "Very low usage")
        case .insufficientData, .none: return text("记录不足", "Not enough history")
        }
    }

    private func durationLabel(until date: Date) -> String {
        guard let current else { return "—" }
        let minutes = max(1, Int(ceil(date.timeIntervalSince(current.timestamp) / 60)))
        if minutes < 60 { return text("约\(minutes)分钟", "~\(minutes)m") }
        if minutes < 24 * 60 {
            let hours = Double(minutes) / 60
            let value = String(format: "%.1f", hours)
            return text("约\(value)h", "~\(value)h")
        }
        let days = Double(minutes) / (24 * 60)
        let value = String(format: "%.1f", days)
        return text("约\(value)天", "~\(value)d")
    }

    private func rateLabel(_ value: Double?) -> String {
        guard let value else { return "—" }
        if value > 0 && value < 0.1 { return "<0.1%" }
        return String(format: "%.1f%%", value)
    }

    private func windowLabel(_ window: QuotaDepletionForecast.Window) -> String {
        switch window {
        case .minutes30: return text("近 30 分钟", "Last 30 min")
        case .hour1: return text("近 1 小时", "Last 1 h")
        case .hours2: return text("近 2 小时", "Last 2 h")
        case .hours5: return text("近 5 小时", "Last 5 h")
        }
    }

    private func text(_ chinese: String, _ english: String) -> String {
        language.text(chinese, english)
    }
}
