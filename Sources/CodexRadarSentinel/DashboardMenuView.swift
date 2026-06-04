import CodexRadarCore
import SwiftUI

struct DashboardMenuView: View {
    @ObservedObject var store: SentinelStore

    private enum Layout {
        static let contentPadding: CGFloat = 12
        static let sectionSpacing: CGFloat = 11
        static let tileSpacing: CGFloat = 8
    }

    private var state: DashboardState {
        store.dashboardState
    }

    private var metrics: DashboardTextSize.Metrics {
        store.menuTextSize.metrics
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                    if store.shouldEmphasizeSpeedAlert {
                        speedAlertBanner
                    }
                    header
                    statusLegend
                    Divider()
                    quotaSection
                    Divider()
                    radarSection
                    predictionSection
                    iqSection
                    if let error = state.lastError {
                        errorSection(error)
                    }
                    Divider()
                    settingsSection
                    previewSection
                }
                .padding(.horizontal, Layout.contentPadding)
                .padding(.top, Layout.contentPadding)
                .padding(.bottom, 8)
            }
            Divider()
            actionButtons
                .padding(.horizontal, Layout.contentPadding)
                .padding(.vertical, 8)
        }
        .frame(width: metrics.width, height: metrics.height, alignment: .leading)
    }

    private var speedAlertBanner: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: metrics.headerIcon, weight: .bold))
            VStack(alignment: .leading, spacing: 2) {
                Text("速蹬窗口开启")
                    .font(.system(size: metrics.headerTitle, weight: .bold))
                Text("Use quota now · \(DisplayFormatters.percent(state.rateLimits?.weeklyRemainingPercent)) weekly left")
                    .font(.system(size: metrics.caption, weight: .medium))
                    .lineLimit(1)
            }
            Spacer()
            Button {
                store.dismissCurrentSpeedAlert()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: metrics.headerIcon, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Dismiss current speed-window alert")
        }
        .foregroundStyle(.white)
        .padding(10)
        .background(Color.red, in: RoundedRectangle(cornerRadius: 8))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: headerSymbol)
                .font(.system(size: metrics.headerIcon, weight: .semibold))
                .foregroundStyle(headerColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.actionLabel)
                    .font(.system(size: metrics.headerTitle, weight: .semibold))
                    .lineLimit(1)
                Text("Updated \(DisplayFormatters.compactDateTime(state.lastUpdatedAt))")
                    .font(.system(size: metrics.caption))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(state.statusTitle)
                .font(.system(size: metrics.badge, weight: .semibold, design: .monospaced))
                .foregroundStyle(headerColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(headerColor.opacity(0.12), in: Capsule())
        }
    }

    private var statusLegend: some View {
        HStack(spacing: Layout.tileSpacing) {
            legendTile(
                title: "Weekly",
                value: DisplayFormatters.percent(state.rateLimits?.weeklyRemainingPercent),
                color: quotaColor
            )
            legendTile(
                title: "IQ",
                value: state.modelIQ?.latest?.iqScore.map(String.init) ?? DisplayFormatters.percentPlaceholder,
                color: iqColor
            )
            legendTile(
                title: "Signal",
                value: signalLabel,
                color: signalColor
            )
        }
    }

    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("Codex Quota", systemImage: "speedometer")
            HStack(spacing: Layout.tileSpacing) {
                quotaTile(
                    title: "Weekly",
                    value: DisplayFormatters.percent(state.rateLimits?.weeklyRemainingPercent),
                    subtitle: "reset \(DisplayFormatters.relativeReset(state.rateLimits?.weeklyBucket?.resetsAt))"
                )
                quotaTile(
                    title: "Short",
                    value: DisplayFormatters.percent(state.rateLimits?.shortRemainingPercent),
                    subtitle: "reset \(DisplayFormatters.relativeReset(state.rateLimits?.shortBucket?.resetsAt))"
                )
            }
            if let planType = state.rateLimits?.snapshot.planType {
                Text("Plan \(planType)")
                    .font(.system(size: metrics.caption))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var radarSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("Reset Radar", systemImage: "dot.radiowaves.left.and.right")
            Text(state.current?.lastWindow?.title ?? "No reset window loaded")
                .font(.system(size: metrics.body, weight: .medium))
                .lineLimit(2)
            HStack {
                labelPair("Window", state.current?.lastWindow?.windowHuman ?? "unknown")
                Spacer()
                labelPair("Scope", state.current?.lastWindow?.scope ?? "unknown")
            }
            Text(state.current?.lastWindow?.summary ?? "CodexRadar current.json has not been loaded yet.")
                .font(.system(size: metrics.label))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var predictionSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("Prediction", systemImage: "chart.line.uptrend.xyaxis")
            HStack {
                labelPair("Level", state.prediction?.level ?? state.current?.prediction?.level ?? "unknown")
                Spacer()
                labelPair("24h", probability(state.prediction?.probability24h ?? state.current?.prediction?.probability24h))
                Spacer()
                labelPair("48h", probability(state.prediction?.probability48h ?? state.current?.prediction?.probability48h))
            }
            Text(state.prediction?.reasoningSummary ?? "No prediction summary loaded.")
                .font(.system(size: metrics.label))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var iqSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("Codex IQ", systemImage: "brain.head.profile")
            HStack {
                labelPair("IQ", state.modelIQ?.latest?.iqScore.map(String.init) ?? "unknown")
                Spacer()
                let passed = state.modelIQ?.latest?.passed.map(String.init) ?? "?"
                let tasks = state.modelIQ?.latest?.tasks.map(String.init) ?? "?"
                labelPair("Probe", "\(passed)/\(tasks)")
                Spacer()
                labelPair("Status", state.modelIQ?.latest?.status ?? "unknown")
            }
        }
    }

    private func errorSection(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("Connection", systemImage: "exclamationmark.triangle")
            Text(error)
                .font(.system(size: metrics.label))
                .foregroundStyle(.secondary)
                .lineLimit(4)
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Settings", systemImage: "slider.horizontal.3")
            Picker("Text size", selection: $store.menuTextSize) {
                ForEach(DashboardTextSize.allCases) { size in
                    Text(size.label).tag(size)
                }
            }
            .pickerStyle(.segmented)
            .font(.system(size: metrics.label))
            Toggle("Prediction alerts", isOn: $store.predictionNotificationsEnabled)
            Toggle("IQ alerts", isOn: $store.iqNotificationsEnabled)
            Toggle("Launch at login", isOn: $store.launchAtLoginEnabled)
        }
        .toggleStyle(.checkbox)
        .font(.system(size: metrics.label))
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Preview", systemImage: "eye")
            Picker("Preview", selection: $store.debugPreview) {
                ForEach(DashboardPreview.allCases) { preview in
                    Text(preview.label).tag(preview)
                }
            }
            .pickerStyle(.segmented)
            .font(.system(size: metrics.label))
            if store.debugPreview != .live {
                Text("UI preview only; notifications still use live data.")
                    .font(.system(size: metrics.caption))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                store.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: metrics.toolbarButtonSize, height: metrics.toolbarButtonSize)
            }
            .help("Refresh")
            Button {
                store.openCodexRadar()
            } label: {
                Image(systemName: "safari")
                    .frame(width: metrics.toolbarButtonSize, height: metrics.toolbarButtonSize)
            }
            .help("Open CodexRadar")
            Button {
                store.openCodexApp()
            } label: {
                Image(systemName: "terminal")
                    .frame(width: metrics.toolbarButtonSize, height: metrics.toolbarButtonSize)
            }
            .help("Open Codex")
            Spacer()
            Button {
                store.quit()
            } label: {
                Image(systemName: "power")
                    .frame(width: metrics.toolbarButtonSize, height: metrics.toolbarButtonSize)
            }
            .help("Quit")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
                .fontWeight(.semibold)
        }
        .font(.system(size: metrics.section))
        .foregroundStyle(.secondary)
    }

    private func legendTile(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: metrics.caption, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: metrics.badge, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func quotaTile(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: metrics.caption))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: metrics.tileValue, weight: .semibold, design: .monospaced))
            Text(subtitle)
                .font(.system(size: metrics.caption))
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(height: metrics.quotaTileHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func labelPair(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: metrics.caption))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: metrics.label))
                .lineLimit(1)
        }
    }

    private func probability(_ value: Double?) -> String {
        guard let value else {
            return "unknown"
        }
        return "\(Int(round(value * 100)))%"
    }

    private var signalLabel: String {
        if state.current?.windowOpen == true {
            return "速蹬"
        }
        if state.rateLimits?.isBlocked == true {
            return "限额"
        }
        return state.predictionLevelLabel ?? "-"
    }

    private var headerSymbol: String {
        if state.current?.windowOpen == true {
            return "bolt.circle.fill"
        }
        if state.rateLimits?.isBlocked == true {
            return "lock.circle.fill"
        }
        return "gauge.with.dots.needle.67percent"
    }

    private var headerColor: Color {
        if state.current?.windowOpen == true {
            return .red
        }
        if state.rateLimits?.isBlocked == true {
            return .orange
        }
        return .accentColor
    }

    private var quotaColor: Color {
        guard let remaining = state.rateLimits?.weeklyRemainingPercent else {
            return .secondary
        }
        if state.rateLimits?.isBlocked == true || remaining <= AppConstants.criticalRemainingPercent {
            return .red
        }
        if remaining <= AppConstants.warningRemainingPercent {
            return .orange
        }
        return .green
    }

    private var iqColor: Color {
        guard let score = state.modelIQ?.latest?.iqScore else {
            return .secondary
        }
        if score < 60 {
            return .red
        }
        if state.modelIQ?.latest?.status?.lowercased() == "red" || score < 90 {
            return .orange
        }
        return .green
    }

    private var signalColor: Color {
        switch signalLabel {
        case "速蹬", "高":
            return .red
        case "限额", "中":
            return .orange
        case "低":
            return .teal
        default:
            return .secondary
        }
    }
}
