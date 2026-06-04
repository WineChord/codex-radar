import CodexRadarCore
import SwiftUI

struct DashboardMenuView: View {
    @ObservedObject var store: SentinelStore

    private enum Layout {
        static let width: CGFloat = 340
        static let height: CGFloat = 430
        static let contentPadding: CGFloat = 12
        static let sectionSpacing: CGFloat = 10
        static let tileSpacing: CGFloat = 8
        static let quotaTileHeight: CGFloat = 66
        static let toolbarButtonSize: CGFloat = 28
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                    header
                    Divider()
                    quotaSection
                    Divider()
                    radarSection
                    predictionSection
                    iqSection
                    if let error = store.state.lastError {
                        errorSection(error)
                    }
                    Divider()
                    settingsSection
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
        .frame(width: Layout.width, height: Layout.height, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: headerSymbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(headerColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.state.actionLabel)
                    .font(.system(.subheadline, weight: .semibold))
                    .lineLimit(1)
                Text("Updated \(DisplayFormatters.compactDateTime(store.state.lastUpdatedAt))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(store.state.statusTitle)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundStyle(headerColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(headerColor.opacity(0.12), in: Capsule())
        }
    }

    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("Codex Quota", systemImage: "speedometer")
            HStack(spacing: Layout.tileSpacing) {
                quotaTile(
                    title: "Weekly",
                    value: DisplayFormatters.percent(store.state.rateLimits?.weeklyRemainingPercent),
                    subtitle: "reset \(DisplayFormatters.relativeReset(store.state.rateLimits?.weeklyBucket?.resetsAt))"
                )
                quotaTile(
                    title: "Short",
                    value: DisplayFormatters.percent(store.state.rateLimits?.shortRemainingPercent),
                    subtitle: "reset \(DisplayFormatters.relativeReset(store.state.rateLimits?.shortBucket?.resetsAt))"
                )
            }
            if let planType = store.state.rateLimits?.snapshot.planType {
                Text("Plan \(planType)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var radarSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Reset Radar", systemImage: "dot.radiowaves.left.and.right")
            Text(store.state.current?.lastWindow?.title ?? "No reset window loaded")
                .font(.subheadline)
                .lineLimit(2)
            HStack {
                labelPair("Window", store.state.current?.lastWindow?.windowHuman ?? "unknown")
                Spacer()
                labelPair("Scope", store.state.current?.lastWindow?.scope ?? "unknown")
            }
            Text(store.state.current?.lastWindow?.summary ?? "CodexRadar current.json has not been loaded yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var predictionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Prediction", systemImage: "chart.line.uptrend.xyaxis")
            HStack {
                labelPair("Level", store.state.prediction?.level ?? store.state.current?.prediction?.level ?? "unknown")
                Spacer()
                labelPair("24h", probability(store.state.prediction?.probability24h ?? store.state.current?.prediction?.probability24h))
                Spacer()
                labelPair("48h", probability(store.state.prediction?.probability48h ?? store.state.current?.prediction?.probability48h))
            }
            Text(store.state.prediction?.reasoningSummary ?? "No prediction summary loaded.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var iqSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Codex IQ", systemImage: "brain.head.profile")
            HStack {
                labelPair("IQ", store.state.modelIQ?.latest?.iqScore.map(String.init) ?? "unknown")
                Spacer()
                let passed = store.state.modelIQ?.latest?.passed.map(String.init) ?? "?"
                let tasks = store.state.modelIQ?.latest?.tasks.map(String.init) ?? "?"
                labelPair("Probe", "\(passed)/\(tasks)")
                Spacer()
                labelPair("Status", store.state.modelIQ?.latest?.status ?? "unknown")
            }
        }
    }

    private func errorSection(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Connection", systemImage: "exclamationmark.triangle")
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Prediction alerts", isOn: $store.predictionNotificationsEnabled)
            Toggle("IQ alerts", isOn: $store.iqNotificationsEnabled)
            Toggle("Launch at login", isOn: $store.launchAtLoginEnabled)
        }
        .toggleStyle(.checkbox)
        .font(.caption)
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                store.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: Layout.toolbarButtonSize, height: Layout.toolbarButtonSize)
            }
            .help("Refresh")
            Button {
                store.openCodexRadar()
            } label: {
                Image(systemName: "safari")
                    .frame(width: Layout.toolbarButtonSize, height: Layout.toolbarButtonSize)
            }
            .help("Open CodexRadar")
            Button {
                store.openCodexApp()
            } label: {
                Image(systemName: "terminal")
                    .frame(width: Layout.toolbarButtonSize, height: Layout.toolbarButtonSize)
            }
            .help("Open Codex")
            Spacer()
            Button {
                store.quit()
            } label: {
                Image(systemName: "power")
                    .frame(width: Layout.toolbarButtonSize, height: Layout.toolbarButtonSize)
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
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func quotaTile(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .monospaced, weight: .semibold))
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(height: Layout.quotaTileHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func labelPair(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .lineLimit(1)
        }
    }

    private func probability(_ value: Double?) -> String {
        guard let value else {
            return "unknown"
        }
        return "\(Int(round(value * 100)))%"
    }

    private var headerSymbol: String {
        if store.state.current?.windowOpen == true {
            return "bolt.circle.fill"
        }
        if store.state.rateLimits?.isBlocked == true {
            return "lock.circle.fill"
        }
        return "gauge.with.dots.needle.67percent"
    }

    private var headerColor: Color {
        if store.state.current?.windowOpen == true {
            return .red
        }
        if store.state.rateLimits?.isBlocked == true {
            return .orange
        }
        return .accentColor
    }
}
