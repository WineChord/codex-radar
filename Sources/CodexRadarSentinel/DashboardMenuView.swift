import CodexRadarCore
import SwiftUI

struct DashboardMenuView: View {
    @ObservedObject var store: SentinelStore
    var scrolling: Bool = true

    private enum Layout {
        static let contentPadding: CGFloat = 12
        static let sectionSpacing: CGFloat = 12
        static let tileSpacing: CGFloat = 8
        static let toolbarCornerRadius: CGFloat = 8
    }

    private var state: DashboardState {
        store.dashboardState
    }

    private var metrics: DashboardTextSize.Metrics {
        store.menuTextSize.metrics
    }

    private var language: AppLanguage {
        store.appLanguage
    }

    private var menuBarTitle: String {
        StatusTitleFormatter.plainTitle(
            for: state,
            metrics: store.selectedStatusMetrics,
            language: language
        )
    }

    var body: some View {
        if scrolling {
            scrollingBody
        } else {
            fullBody
        }
    }

    private var scrollingBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: true) {
                menuContent
            }
            Divider()
            toolbarContent
        }
        .frame(width: metrics.width, height: metrics.height, alignment: .leading)
    }

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            menuContent
            Divider()
            toolbarContent
        }
        .frame(width: metrics.width, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var menuContent: some View {
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
            updateSection
            previewSection
        }
        .padding(.horizontal, Layout.contentPadding)
        .padding(.top, Layout.contentPadding)
        .padding(.bottom, 8)
    }

    private var toolbarContent: some View {
        actionButtons
            .padding(.horizontal, Layout.contentPadding)
            .padding(.vertical, 8)
    }

    private var speedAlertBanner: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: metrics.headerIcon, weight: .bold))
            VStack(alignment: .leading, spacing: 2) {
                Text(text("速蹬窗口开启", "Speed window open"))
                    .font(.system(size: metrics.headerTitle, weight: .bold))
                Text(text(
                    "建议尽快使用 · 周额度剩余 \(DisplayFormatters.percent(state.rateLimits?.weeklyRemainingPercent))",
                    "Use quota now · \(DisplayFormatters.percent(state.rateLimits?.weeklyRemainingPercent)) weekly left"
                ))
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
            .help(text("关闭本次速蹬强调", "Dismiss current speed-window alert"))
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
                Text(actionText)
                    .font(.system(size: metrics.headerTitle, weight: .semibold))
                    .lineLimit(1)
                Text("\(text("更新", "Updated")) \(DisplayFormatters.compactDateTime(state.lastUpdatedAt))")
                    .font(.system(size: metrics.caption))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(menuBarTitle)
                .font(.system(size: metrics.badge, weight: .semibold, design: .monospaced))
                .foregroundStyle(headerColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(headerColor.opacity(0.12), in: Capsule())
        }
    }

    private var statusLegend: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle(text("状态栏含义", "Menu Bar"), systemImage: "menubar.rectangle")
            Text(text(
                "菜单栏按“周额度 / IQ / 信号”拼接；下面可以选择显示哪些项。",
                "The menu bar joins Weekly / IQ / Signal; choose visible segments below."
            ))
            .font(.system(size: metrics.caption))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            HStack(spacing: Layout.tileSpacing) {
                legendTile(metric: .weeklyQuota, color: quotaColor)
                legendTile(metric: .codexIQ, color: iqColor)
                legendTile(metric: .signal, color: signalColor)
            }
        }
    }

    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle(text("Codex 额度", "Codex Quota"), systemImage: "speedometer")
            HStack(spacing: Layout.tileSpacing) {
                quotaTile(
                    title: text("周额度", "Weekly"),
                    value: DisplayFormatters.percent(state.rateLimits?.weeklyRemainingPercent),
                    resetAt: state.rateLimits?.weeklyBucket?.resetsAt
                )
                quotaTile(
                    title: text("短窗", "Short"),
                    value: DisplayFormatters.percent(state.rateLimits?.shortRemainingPercent),
                    resetAt: state.rateLimits?.shortBucket?.resetsAt
                )
            }
            if let planType = state.rateLimits?.snapshot.planType {
                Text("\(text("套餐", "Plan")) \(planType)")
                    .font(.system(size: metrics.caption))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var radarSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("Reset Radar", systemImage: "dot.radiowaves.left.and.right")
            Text(state.current?.lastWindow?.title ?? text("还没有加载 reset 窗口", "No reset window loaded"))
                .font(.system(size: metrics.body, weight: .medium))
                .lineLimit(2)
            HStack {
                labelPair(text("窗口", "Window"), state.current?.lastWindow?.windowHuman ?? text("未知", "unknown"))
                Spacer()
                labelPair(text("范围", "Scope"), state.current?.lastWindow?.scope ?? text("未知", "unknown"))
            }
            Text(state.current?.lastWindow?.summary ?? text(
                "还没有读取到 CodexRadar current.json。",
                "CodexRadar current.json has not been loaded yet."
            ))
            .font(.system(size: metrics.label))
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
    }

    private var predictionSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle(text("Prediction 预测", "Prediction"), systemImage: "chart.line.uptrend.xyaxis")
            HStack {
                labelPair(text("等级", "Level"), predictionLevelText(state.prediction?.level ?? state.current?.prediction?.level))
                Spacer()
                labelPair("24h", probability(state.prediction?.probability24h ?? state.current?.prediction?.probability24h))
                Spacer()
                labelPair("48h", probability(state.prediction?.probability48h ?? state.current?.prediction?.probability48h))
            }
            Text(state.prediction?.reasoningSummary ?? text(
                "还没有读取到预测摘要。",
                "No prediction summary loaded."
            ))
            .font(.system(size: metrics.label))
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
    }

    private var iqSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("Codex IQ", systemImage: "brain.head.profile")
            HStack {
                labelPair("IQ", DisplayFormatters.iqScore(state.modelIQ?.latest?.iqScore))
                Spacer()
                let passed = state.modelIQ?.latest?.passed.map(String.init) ?? "?"
                let tasks = state.modelIQ?.latest?.tasks.map(String.init) ?? "?"
                labelPair(text("探针", "Probe"), "\(passed)/\(tasks)")
                Spacer()
                labelPair(text("状态", "Status"), state.modelIQ?.latest?.status ?? text("未知", "unknown"))
            }
        }
    }

    private func errorSection(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle(text("连接", "Connection"), systemImage: "exclamationmark.triangle")
            Text(error)
                .font(.system(size: metrics.label))
                .foregroundStyle(.secondary)
                .lineLimit(4)
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(text("显示与提醒", "Display & Alerts"), systemImage: "slider.horizontal.3")
            settingRow(title: text("语言", "Language")) {
                Picker(text("语言", "Language"), selection: $store.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.label).tag(language)
                    }
                }
                .pickerStyle(.segmented)
            }
            settingRow(title: text("字号", "Text size")) {
                Picker(text("字号", "Text size"), selection: $store.menuTextSize) {
                    ForEach(DashboardTextSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .pickerStyle(.segmented)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(text("状态栏显示", "Menu bar segments"))
                    .font(.system(size: metrics.caption, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: Layout.tileSpacing) {
                    metricToggle(.weeklyQuota)
                    metricToggle(.codexIQ)
                    metricToggle(.signal)
                }
            }
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Layout.tileSpacing),
                    GridItem(.flexible(), spacing: Layout.tileSpacing),
                ],
                alignment: .leading,
                spacing: 7
            ) {
                Toggle(text("Prediction 提醒", "Prediction alerts"), isOn: $store.predictionNotificationsEnabled)
                Toggle(text("IQ 提醒", "IQ alerts"), isOn: $store.iqNotificationsEnabled)
                Toggle(text("通知声音", "Notification sound"), isOn: $store.notificationSoundEnabled)
                Toggle(text("登录时启动", "Launch at login"), isOn: $store.launchAtLoginEnabled)
            }
        }
        .toggleStyle(.checkbox)
        .font(.system(size: metrics.label))
    }

    private var updateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(text("版本更新", "Updates"), systemImage: "arrow.down.app")
            HStack(alignment: .center, spacing: Layout.tileSpacing) {
                Toggle(text("自动更新", "Auto update"), isOn: $store.automaticUpdatesEnabled)
                    .toggleStyle(.checkbox)
                    .font(.system(size: metrics.label))
                Spacer()
                Text("v\(AppConstants.appVersion)")
                    .font(.system(size: metrics.caption, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text(updateStatusText)
                .font(.system(size: metrics.caption))
                .foregroundStyle(updateStatusColor)
                .lineLimit(2)
            HStack(spacing: Layout.tileSpacing) {
                compactActionButton(title: text("检查更新", "Check"), systemImage: "arrow.clockwise") {
                    store.checkForUpdatesNow()
                }
                compactActionButton(title: "Changelog", systemImage: "doc.text") {
                    store.openLatestReleaseNotes()
                }
                compactActionButton(
                    title: "Prompts",
                    systemImage: "text.quote",
                    help: text("打开 PROMPTS.md", "Open PROMPTS.md")
                ) {
                    store.openPromptLog()
                }
                compactActionButton(title: "GitHub ★", systemImage: "star") {
                    store.openGitHubRepository()
                }
            }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(text("调试预览", "Preview"), systemImage: "eye")
            Picker(text("预览", "Preview"), selection: $store.debugPreview) {
                ForEach(DashboardPreview.allCases) { preview in
                    Text(preview.label(language: language)).tag(preview)
                }
            }
            .pickerStyle(.segmented)
            .font(.system(size: metrics.label))
            Text(text(
                "只预览 UI；真实通知和去重仍使用 live 数据。",
                "UI preview only; notifications still use live data."
            ))
            .font(.system(size: metrics.caption))
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            toolbarButton(title: text("刷新", "Refresh"), systemImage: "arrow.clockwise") {
                store.refreshNow()
            }
            toolbarButton(title: "Radar", systemImage: "safari") {
                store.openCodexRadar()
            }
            toolbarButton(title: "Codex", systemImage: "terminal") {
                store.openCodexApp()
            }
            toolbarButton(title: text("退出", "Quit"), systemImage: "power") {
                store.quit()
            }
        }
    }

    private func toolbarButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: metrics.section, weight: .semibold))
                Text(title)
                    .font(.system(size: metrics.caption, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: metrics.toolbarHeight)
            .contentShape(RoundedRectangle(cornerRadius: Layout.toolbarCornerRadius))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: Layout.toolbarCornerRadius))
        .help(title)
    }

    private func compactActionButton(
        title: String,
        systemImage: String,
        help: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: metrics.caption, weight: .semibold))
                Text(title)
                    .font(.system(size: metrics.caption, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 7)
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
        .help(help ?? title)
    }

    private func settingRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(.system(size: metrics.caption, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: metrics.settingLabelWidth, alignment: .leading)
            content()
                .font(.system(size: metrics.label))
                .frame(maxWidth: .infinity)
        }
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

    private func legendTile(metric: StatusMetric, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(metric.label(language: language))
                .font(.system(size: metrics.caption, weight: .medium))
                .foregroundStyle(.secondary)
            Text(metric.value(for: state, language: language))
                .font(.system(size: metrics.badge, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func metricToggle(_ metric: StatusMetric) -> some View {
        let isEnabled = store.isStatusMetricEnabled(metric)
        return Button {
            store.setStatusMetric(metric, enabled: !isEnabled)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                Text(metric.label(language: language))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.system(size: metrics.caption, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .padding(.horizontal, 5)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .help(metric.label(language: language))
    }

    private func quotaTile(title: String, value: String, resetAt: Int?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: metrics.caption))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: metrics.tileValue, weight: .semibold, design: .monospaced))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(text("重置", "reset")) \(DisplayFormatters.relativeReset(resetAt))")
                Text(DisplayFormatters.compactEpochDateTime(resetAt))
            }
            .font(.system(size: metrics.caption))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
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
            return text("未知", "unknown")
        }
        return "\(Int(round(value * 100)))%"
    }

    private func predictionLevelText(_ level: String?) -> String {
        switch level?.lowercased() {
        case "high":
            return text("高", "high")
        case "medium":
            return text("中", "medium")
        case "low":
            return text("低", "low")
        default:
            return text("未知", "unknown")
        }
    }

    private func text(_ zhHans: String, _ en: String) -> String {
        language.text(zhHans, en)
    }

    private var actionText: String {
        if state.current?.windowOpen == true {
            return text("速蹬窗口开启", "Speed window open")
        }
        if state.rateLimits?.isBlocked == true {
            return text("本机限额中", "Local limit reached")
        }
        if state.recentResetClosed {
            return text("limit reset 已确认", "limit reset confirmed")
        }
        return text("等待", "Waiting")
    }

    private var signalLabel: String {
        StatusMetric.signal.value(for: state, language: language)
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
        case "速蹬", "high", "高":
            return .red
        case "限额", "med", "medium", "中":
            return .orange
        case "低", "low":
            return .teal
        default:
            return .secondary
        }
    }

    private var updateStatusText: String {
        switch store.updatePhase {
        case .idle:
            return text(
                "默认自动检查 GitHub Release；发现新版会校验并安装。",
                "Auto-checks GitHub Releases by default; verified updates install automatically."
            )
        default:
            return store.updatePhase.label(language: language)
        }
    }

    private var updateStatusColor: Color {
        switch store.updatePhase {
        case .failed:
            return .red
        case .downloading, .installing, .available:
            return .accentColor
        default:
            return .secondary
        }
    }
}
