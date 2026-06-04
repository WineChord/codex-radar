import CodexRadarCore
import SwiftUI

struct DashboardMenuView: View {
    @ObservedObject var store: SentinelStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            actionButtons
        }
        .padding(14)
        .frame(width: 380, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: headerSymbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(headerColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.state.actionLabel)
                    .font(.headline)
                    .lineLimit(1)
                Text("Updated \(DisplayFormatters.compactDateTime(store.state.lastUpdatedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(store.state.statusTitle)
                .font(.system(.body, design: .monospaced, weight: .semibold))
                .lineLimit(1)
        }
    }

    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Codex Quota", systemImage: "speedometer")
            HStack(spacing: 10) {
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
                .lineLimit(3)
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
                .lineLimit(3)
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
            Button("Refresh") {
                store.refreshNow()
            }
            Button("Radar") {
                store.openCodexRadar()
            }
            Button("Codex") {
                store.openCodexApp()
            }
            Spacer()
            Button("Quit") {
                store.quit()
            }
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
        .padding(10)
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
