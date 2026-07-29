import Charts
import CodexRadarCore
import SwiftUI

struct QuotaHistoryChartView: View {
    let timeline: QuotaHistoryTimeline
    @Binding var range: QuotaHistoryRange
    let endingAt: Date
    let language: AppLanguage
    let metrics: DashboardTextSize.Metrics
    let storageUnavailable: Bool

    @State private var selectedSample: QuotaHistorySample?

    private struct ChartPoint: Identifiable {
        let sample: QuotaHistorySample
        let segment: Int

        var id: Date {
            sample.timestamp
        }
    }

    private var visibleSamples: [QuotaHistorySample] {
        timeline.samples(in: range, endingAt: endingAt)
    }

    private var chartPoints: [ChartPoint] {
        let displaySamples = timeline.displaySamples(
            in: range,
            endingAt: endingAt
        )
        var previousTimestamp: Date?
        var segment = 0
        return displaySamples.map { sample in
            if let previousTimestamp,
               sample.timestamp.timeIntervalSince(previousTimestamp)
                    > range.continuityGap {
                segment += 1
            }
            previousTimestamp = sample.timestamp
            return ChartPoint(sample: sample, segment: segment)
        }
    }

    private var resetEvents: [QuotaHistoryResetEvent] {
        timeline.resetEvents(in: range, endingAt: endingAt)
    }

    private var summary: QuotaHistorySummary {
        timeline.summary(in: range, endingAt: endingAt)
    }

    private var presentedSample: QuotaHistorySample? {
        selectedSample ?? visibleSamples.last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            rangePicker

            if storageUnavailable {
                Label(
                    text(
                        "本地历史暂时无法安全读写",
                        "Local history is temporarily unavailable"
                    ),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: metrics.caption, weight: .medium))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }

            if visibleSamples.isEmpty {
                emptyState
            } else {
                sampleHeader
                quotaChart
                chartFooter
            }
        }
        .onChange(of: range) { _ in
            selectedSample = nil
        }
    }

    private var rangePicker: some View {
        Picker(
            text("历史范围", "History range"),
            selection: $range
        ) {
            ForEach(QuotaHistoryRange.allCases, id: \.self) { option in
                Text(rangeLabel(option)).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel(text("额度历史范围", "Quota history range"))
    }

    private var sampleHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(
                    presentedSample.map {
                        formatPercent($0.remainingPercent)
                    } ?? "—"
                )
                .font(.system(
                    size: metrics.tileValue,
                    weight: .semibold,
                    design: .rounded
                ))
                .monospacedDigit()

                if let sample = presentedSample {
                    Text(sampleTimestamp(sample.timestamp))
                        .font(.system(size: metrics.caption))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            if let sample = presentedSample,
               let previous = timeline.previousSample(before: sample) {
                let change =
                    sample.remainingPercent - previous.remainingPercent
                VStack(alignment: .trailing, spacing: 1) {
                    Text(changeText(change))
                        .font(.system(
                            size: metrics.label,
                            weight: .semibold,
                            design: .rounded
                        ))
                        .monospacedDigit()
                        .foregroundStyle(changeColor(change))
                    Text(
                        timeline.isResetSample(sample)
                            ? text("观察到重置", "Observed reset")
                            : text("较上次记录", "vs previous sample")
                    )
                    .font(.system(size: metrics.caption))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var quotaChart: some View {
        Chart {
            ForEach(chartPoints) { point in
                AreaMark(
                    x: .value(
                        text("时间", "Time"),
                        point.sample.timestamp
                    ),
                    yStart: .value(text("最低", "Minimum"), 0),
                    yEnd: .value(
                        text("剩余", "Remaining"),
                        point.sample.remainingPercent
                    ),
                    series: .value("Segment", point.segment)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.28),
                            Color.blue.opacity(0.04),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.linear)

                LineMark(
                    x: .value(
                        text("时间", "Time"),
                        point.sample.timestamp
                    ),
                    y: .value(
                        text("剩余", "Remaining"),
                        point.sample.remainingPercent
                    ),
                    series: .value("Segment", point.segment)
                )
                .foregroundStyle(Color.blue)
                .lineStyle(StrokeStyle(
                    lineWidth: 2,
                    lineCap: .round,
                    lineJoin: .round
                ))
                .interpolationMethod(.linear)
            }

            if chartPoints.count == 1, let point = chartPoints.first {
                PointMark(
                    x: .value(
                        text("时间", "Time"),
                        point.sample.timestamp
                    ),
                    y: .value(
                        text("剩余", "Remaining"),
                        point.sample.remainingPercent
                    )
                )
                .foregroundStyle(Color.blue)
                .symbolSize(34)
            }

            if chartPoints.count > 1, let point = chartPoints.last {
                PointMark(
                    x: .value(
                        text("最新时间", "Latest time"),
                        point.sample.timestamp
                    ),
                    y: .value(
                        text("最新剩余", "Latest remaining"),
                        point.sample.remainingPercent
                    )
                )
                .foregroundStyle(Color.blue)
                .symbolSize(28)
            }

            ForEach(resetEvents) { event in
                PointMark(
                    x: .value(text("重置", "Reset"), event.timestamp),
                    y: .value(
                        text("重置后剩余", "Remaining after reset"),
                        event.remainingPercent
                    )
                )
                .foregroundStyle(.green)
                .symbolSize(44)
            }

            if let selectedSample {
                RuleMark(
                    x: .value(
                        text("所选时间", "Selected time"),
                        selectedSample.timestamp
                    )
                )
                .foregroundStyle(.secondary.opacity(0.8))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                PointMark(
                    x: .value(
                        text("所选时间", "Selected time"),
                        selectedSample.timestamp
                    ),
                    y: .value(
                        text("所选剩余", "Selected remaining"),
                        selectedSample.remainingPercent
                    )
                )
                .foregroundStyle(.primary)
                .symbolSize(62)
            }
        }
        .chartXScale(
            domain: endingAt.addingTimeInterval(-range.duration)...endingAt,
            range: .plotDimension(startPadding: 6, endPadding: 10)
        )
        .chartYScale(domain: 0...100)
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                AxisGridLine()
                    .foregroundStyle(Color.gray.opacity(0.18))
                AxisValueLabel {
                    if let percent = value.as(Int.self) {
                        Text("\(percent)%")
                    }
                }
                .font(.system(size: metrics.caption))
                .foregroundStyle(Color.gray)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                    .foregroundStyle(Color.gray.opacity(0.12))
                AxisTick()
                    .foregroundStyle(Color.gray.opacity(0.35))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(axisTimestamp(date))
                    }
                }
                .font(.system(size: metrics.caption))
                .foregroundStyle(Color.gray)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            selectSample(
                                at: location,
                                proxy: proxy,
                                geometry: geometry
                            )
                        case .ended:
                            selectedSample = nil
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                selectSample(
                                    at: value.location,
                                    proxy: proxy,
                                    geometry: geometry
                                )
                            }
                    )
            }
        }
        .frame(height: 154)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text(
            "周额度剩余历史曲线",
            "Weekly quota remaining history chart"
        ))
        .accessibilityValue(chartAccessibilityValue)
        .accessibilityHint(text(
            "移动鼠标、拖动或使用可调操作查看其他记录",
            "Move the pointer, drag, or adjust to inspect another sample"
        ))
        .accessibilityAdjustableAction { direction in
            adjustSelection(direction)
        }
    }

    private var chartFooter: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(text(
                "区间观测消耗 \(formatPoints(summary.observedConsumption))",
                "Observed use \(formatPoints(summary.observedConsumption))"
            ))
            Spacer(minLength: 4)
            Label(
                text(
                    "\(summary.resetCount) 次重置",
                    "\(summary.resetCount) resets"
                ),
                systemImage: "arrow.counterclockwise"
            )
        }
        .font(.system(size: metrics.caption))
        .foregroundStyle(.secondary)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(
                text("开始记录中", "Recording starts now"),
                systemImage: "clock.arrow.circlepath"
            )
            .font(.system(size: metrics.label, weight: .semibold))
            Text(text(
                "读取到周额度后会在本机留下第一个点；之后的变化、重置与数据断档会按实际观测显示。",
                "The first local point appears after weekly quota loads. Later changes, resets, and data gaps are shown exactly as observed."
            ))
            .font(.system(size: metrics.caption))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var chartAccessibilityValue: String {
        guard let sample = presentedSample else {
            return text("尚无记录", "No samples yet")
        }
        return text(
            "\(sampleTimestamp(sample.timestamp))，剩余 \(formatPercent(sample.remainingPercent))",
            "\(sampleTimestamp(sample.timestamp)), \(formatPercent(sample.remainingPercent)) remaining"
        )
    }

    private func selectSample(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        let plotFrame = geometry[proxy.plotAreaFrame]
        guard plotFrame.contains(location) else {
            return
        }
        let relativeX = location.x - plotFrame.origin.x
        guard let date: Date = proxy.value(atX: relativeX) else {
            return
        }
        selectedSample = timeline.nearestSample(
            to: date,
            in: range,
            endingAt: endingAt
        )
    }

    private func adjustSelection(
        _ direction: AccessibilityAdjustmentDirection
    ) {
        guard !visibleSamples.isEmpty else {
            return
        }
        let current = selectedSample ?? visibleSamples.last
        let index = current.flatMap {
            visibleSamples.firstIndex(of: $0)
        } ?? visibleSamples.count - 1
        switch direction {
        case .increment:
            selectedSample = visibleSamples[
                min(visibleSamples.count - 1, index + 1)
            ]
        case .decrement:
            selectedSample = visibleSamples[max(0, index - 1)]
        @unknown default:
            return
        }
    }

    private func rangeLabel(_ value: QuotaHistoryRange) -> String {
        switch value {
        case .hours24:
            return text("24 小时", "24 hours")
        case .days7:
            return text("7 天", "7 days")
        case .days30:
            return text("30 天", "30 days")
        }
    }

    private func sampleTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language == .zhHans
            ? Locale(identifier: "zh_Hans_CN")
            : Locale(identifier: "en_US")
        formatter.dateFormat = language == .zhHans
            ? "M月d日 HH:mm"
            : "MMM d, HH:mm"
        return formatter.string(from: date)
    }

    private func axisTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language == .zhHans
            ? Locale(identifier: "zh_Hans_CN")
            : Locale(identifier: "en_US")
        switch range {
        case .hours24:
            formatter.dateFormat = "HH:mm"
        case .days7:
            formatter.dateFormat = language == .zhHans ? "M/d" : "MMM d"
        case .days30:
            formatter.dateFormat = language == .zhHans ? "M/d" : "MMM d"
        }
        return formatter.string(from: date)
    }

    private func formatPercent(_ value: Double) -> String {
        "\(formatNumber(value))%"
    }

    private func formatPoints(_ value: Double) -> String {
        text(
            "\(formatNumber(value)) 个百分点",
            "\(formatNumber(value)) pp"
        )
    }

    private func formatNumber(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.05 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    private func changeText(_ value: Double) -> String {
        let prefix = value > 0 ? "+" : ""
        return "\(prefix)\(formatNumber(value)) pp"
    }

    private func changeColor(_ value: Double) -> Color {
        if value > 0 {
            return .green
        }
        if value < 0 {
            return .orange
        }
        return .secondary
    }

    private func text(_ zhHans: String, _ en: String) -> String {
        language.text(zhHans, en)
    }
}
