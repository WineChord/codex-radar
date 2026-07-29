import AppKit
import CodexRadarCore
import SwiftUI
import UniformTypeIdentifiers

private extension UTType {
    static let codexRadarDashboardSection = UTType(
        exportedAs: "com.codexradar.sentinel.dashboard-section"
    )
}

private enum DashboardVisualTestOverrides {
    static let expandsSecondarySections =
        ProcessInfo.processInfo.environment[
            "CODEX_RADAR_VISUAL_TEST_EXPAND_SECONDARY"
        ] == "1"
    static let expandsModelIQ =
        ProcessInfo.processInfo.environment[
            "CODEX_RADAR_VISUAL_TEST_EXPAND_MODEL_IQ"
        ] == "1"
    static let expandsQuotaHistory =
        ProcessInfo.processInfo.environment[
            "CODEX_RADAR_VISUAL_TEST_EXPAND_QUOTA_HISTORY"
        ] == "1"
    static let showsLayoutEditor =
        ProcessInfo.processInfo.environment[
            "CODEX_RADAR_VISUAL_TEST_LAYOUT_EDITOR"
        ] == "1"
}

struct DashboardMenuView: View {
    @ObservedObject var store: SentinelStore
    @State private var copiedCommunityPrompt = false
    @State private var expandedTextKeys: Set<String> = []
    @State private var customizesLayout: Bool
    @State private var draggedDashboardSection: DashboardSection?
    @State private var dashboardSectionDragPreview:
        [DashboardSection]?
    @State private var showsResetCreditProtectionConfirmation = false
    var scrolling: Bool = true

    init(
        store: SentinelStore,
        scrolling: Bool = true,
        customizesLayoutInitially: Bool =
            DashboardVisualTestOverrides.showsLayoutEditor
    ) {
        self.store = store
        self.scrolling = scrolling
        _customizesLayout = State(
            initialValue: customizesLayoutInitially
        )
    }

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
            language: language,
            options: store.statusBarDisplayOptions
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
                if customizesLayout {
                    layoutEditorContent
                } else {
                    menuContent
                }
            }
            Divider()
            toolbarContent
        }
        .frame(width: metrics.width, height: metrics.height, alignment: .leading)
    }

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if customizesLayout {
                layoutEditorContent
            } else {
                menuContent
            }
            Divider()
            toolbarContent
        }
        .frame(width: metrics.width, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var menuContent: some View {
        VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
            fixedStatusContent
            ForEach(store.dashboardLayout.order) { section in
                if visibilityResolution(for: section).isVisible {
                    dashboardSection(section)
                }
            }
        }
        .padding(.horizontal, Layout.contentPadding)
        .padding(.top, Layout.contentPadding)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func dashboardSection(_ section: DashboardSection) -> some View {
        switch section {
        case .quota:
            quotaSection
        case .modelIQ:
            iqSection
        case .resetCredits:
            resetCreditSection
        case .usagePace:
            quotaPacingSection
        case .insights:
            codexRadarInsightsSection
        case .radarDetails:
            codexRadarDetailsSection
        case .menuBarGuide:
            statusLegend
        case .displayAndAlerts:
            settingsSection
        case .updates:
            updateSection
        case .preview:
            previewSection
        }
    }

    @ViewBuilder
    private var fixedStatusContent: some View {
        if store.shouldEmphasizeSpeedAlert {
            speedAlertBanner
        }
        header
        if let error = state.lastError {
            errorSection(error)
        }
    }

    private var layoutEditorContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            fixedStatusContent
            if forcesResetCreditSectionExpansion {
                resetCreditSection
            }
            if updateRequiresAttention {
                updateSection
            }
            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Label(
                    text("自定义菜单布局", "Customize menu layout"),
                    systemImage: "rectangle.3.group"
                )
                .font(.system(size: metrics.headerTitle, weight: .semibold))
                Text(text(
                    "拖动调整模块顺序；选择模块和子项是否显示、是否默认展开。",
                    "Reorder sections, then choose what appears and opens by default."
                ))
                .font(.system(size: metrics.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(
                    Array(layoutEditorOrder.enumerated()),
                    id: \.element.id
                ) { index, section in
                    layoutEditorRow(section, index: index)
                }
            }
            .onDrop(
                of: [.codexRadarDashboardSection],
                isTargeted: nil
            ) { _ in
                commitDashboardSectionDrag()
                return true
            }

            Text(text(
                "隐藏只影响菜单展示，不会停止数据记录、提醒或重置卡自动使用。当前结论、紧急提示和连接错误始终显示；需要处理的重置卡或更新状态会临时显示并展开。",
                "Hiding changes only the menu. Recording, alerts, and reset-credit auto-use continue. The current result, urgent alerts, and connection errors always remain visible; reset-credit or update states that need attention temporarily appear expanded."
            ))
            .font(.system(size: metrics.caption))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(text("恢复默认布局", "Restore default layout")) {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        cancelDashboardSectionDrag()
                        store.resetDashboardLayout()
                    }
                }
                .font(.system(size: metrics.label, weight: .medium))
                Spacer()
            }
        }
        .padding(.horizontal, Layout.contentPadding)
        .padding(.vertical, Layout.contentPadding)
        .onDisappear {
            cancelDashboardSectionDrag()
        }
    }

    private func layoutEditorRow(
        _ section: DashboardSection,
        index: Int
    ) -> some View {
        let isVisible = store.isDashboardSectionVisible(section)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(
                        size: metrics.section,
                        weight: .semibold
                    ))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                    .onDrag {
                        beginDashboardSectionDrag(section)
                    }
                    .help(text("拖动调整顺序", "Drag to reorder"))
                    .accessibilityLabel(text(
                        "拖动 \(section.label(language: language)) 调整顺序",
                        "Drag \(section.label(language: language)) to reorder"
                    ))

                Image(systemName: section.systemImage)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)

                Text(section.layoutEditorLabel(language: language))
                    .font(.system(
                        size: metrics.label,
                        weight: .medium
                    ))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 4)

                Button {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        cancelDashboardSectionDrag()
                        store.moveDashboardSection(
                            section,
                            to: index - 1
                        )
                    }
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                .disabled(index == 0)
                .help(text("上移", "Move up"))
                .accessibilityLabel(text(
                    "上移 \(section.label(language: language))",
                    "Move \(section.label(language: language)) up"
                ))

                Button {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        cancelDashboardSectionDrag()
                        store.moveDashboardSection(
                            section,
                            to: index + 1
                        )
                    }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                .disabled(
                    index == store.dashboardLayout.order.count - 1
                )
                .help(text("下移", "Move down"))
                .accessibilityLabel(text(
                    "下移 \(section.label(language: language))",
                    "Move \(section.label(language: language)) down"
                ))
            }

            HStack(spacing: 14) {
                Color.clear
                    .frame(width: 44, height: 1)

                Toggle(
                    text("显示", "Show"),
                    isOn: storedVisibilityBinding(for: section)
                )
                .toggleStyle(.checkbox)
                .font(.system(
                    size: metrics.caption,
                    weight: .medium
                ))
                .accessibilityLabel(text(
                    "显示 \(section.label(language: language))",
                    "Show \(section.label(language: language))"
                ))

                Toggle(
                    text("默认展开", "Open by default"),
                    isOn: storedExpansionBinding(for: section)
                )
                .toggleStyle(.checkbox)
                .font(.system(
                    size: metrics.caption,
                    weight: .medium
                ))
                .disabled(!isVisible)
                .accessibilityLabel(text(
                    "\(section.label(language: language)) 默认展开",
                    "Open \(section.label(language: language)) by default"
                ))

                Spacer(minLength: 0)
            }
            .padding(.top, 6)

            ForEach(DashboardDisclosure.children(of: section)) {
                disclosure in
                Divider()
                    .padding(.leading, 35)
                    .padding(.top, 6)
                layoutEditorDisclosureRow(disclosure)
                    .padding(.top, 6)
            }
        }
        .accessibilityValue(text(
            "第 \(index + 1) 项，\(isVisible ? "显示" : "隐藏")",
            "Position \(index + 1), \(isVisible ? "shown" : "hidden")"
        ))
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onDrop(
            of: [.codexRadarDashboardSection],
            delegate: DashboardSectionDropDelegate(
                targetSection: section,
                draggedSection: $draggedDashboardSection,
                sections: layoutEditorOrder,
                move: { movedSection, targetIndex in
                    withAnimation(.easeInOut(duration: 0.12)) {
                        previewDashboardSectionMove(
                            movedSection,
                            to: targetIndex
                        )
                    }
                },
                commit: commitDashboardSectionDrag
            )
        )
    }

    private func layoutEditorDisclosureRow(
        _ disclosure: DashboardDisclosure
    ) -> some View {
        let isVisible = store.isDashboardDisclosureVisible(disclosure)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.turn.down.right")
                    .frame(width: 18)
                    .foregroundStyle(.tertiary)

                Image(systemName: disclosure.systemImage)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)

                Text(disclosure.label(language: language))
                    .font(.system(size: metrics.caption, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 4)
            }

            HStack(spacing: 14) {
                Color.clear
                    .frame(width: 44, height: 1)

                Toggle(
                    text("显示", "Show"),
                    isOn: storedDisclosureVisibilityBinding(
                        for: disclosure
                    )
                )
                .toggleStyle(.checkbox)
                .font(.system(size: metrics.caption, weight: .medium))
                .accessibilityLabel(text(
                    "显示 \(disclosure.label(language: language))",
                    "Show \(disclosure.label(language: language))"
                ))

                Toggle(
                    text("默认展开", "Open by default"),
                    isOn: storedDisclosureExpansionBinding(
                        for: disclosure
                    )
                )
                .toggleStyle(.checkbox)
                .font(.system(size: metrics.caption, weight: .medium))
                .disabled(!isVisible)
                .accessibilityLabel(text(
                    "\(disclosure.label(language: language)) 默认展开",
                    "Open \(disclosure.label(language: language)) by default"
                ))

                Spacer(minLength: 0)
            }
        }
        .padding(.leading, 27)
    }

    private var layoutEditorOrder: [DashboardSection] {
        dashboardSectionDragPreview ?? store.dashboardLayout.order
    }

    private func beginDashboardSectionDrag(
        _ section: DashboardSection
    ) -> NSItemProvider {
        draggedDashboardSection = section
        dashboardSectionDragPreview = store.dashboardLayout.order

        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier:
                UTType.codexRadarDashboardSection.identifier,
            visibility: .ownProcess
        ) { completion in
            completion(Data(section.rawValue.utf8), nil)
            return nil
        }
        return provider
    }

    private func previewDashboardSectionMove(
        _ section: DashboardSection,
        to targetIndex: Int
    ) {
        var preview = store.dashboardLayout
        preview.setOrder(layoutEditorOrder)
        preview.move(section, to: targetIndex)
        dashboardSectionDragPreview = preview.order
    }

    private func commitDashboardSectionDrag() {
        if let dashboardSectionDragPreview {
            store.setDashboardSectionOrder(
                dashboardSectionDragPreview
            )
        }
        cancelDashboardSectionDrag()
    }

    private func cancelDashboardSectionDrag() {
        draggedDashboardSection = nil
        dashboardSectionDragPreview = nil
    }

    private func storedExpansionBinding(
        for section: DashboardSection
    ) -> Binding<Bool> {
        Binding(
            get: {
                store.isDashboardSectionExpanded(section)
            },
            set: { expanded in
                store.setDashboardSection(section, expanded: expanded)
            }
        )
    }

    private func storedVisibilityBinding(
        for section: DashboardSection
    ) -> Binding<Bool> {
        Binding(
            get: {
                store.isDashboardSectionVisible(section)
            },
            set: { visible in
                store.setDashboardSection(section, visible: visible)
            }
        )
    }

    private func renderedExpansionBinding(
        for section: DashboardSection
    ) -> Binding<Bool> {
        Binding(
            get: {
                if DashboardVisualTestOverrides.expandsSecondarySections {
                    return true
                }
                return expansionResolution(for: section).isExpanded
            },
            set: { expanded in
                let resolution = expansionResolution(for: section)
                if !expanded, !resolution.canCollapse {
                    return
                }
                store.setDashboardSection(section, expanded: expanded)
            }
        )
    }

    private func expansionResolution(
        for section: DashboardSection
    ) -> DashboardSectionExpansionPolicy.Resolution {
        DashboardSectionExpansionPolicy.resolve(
            section: section,
            preferredExpanded:
                store.isDashboardSectionExpanded(section),
            resetCreditStatus: store.resetCreditProtectionStatus,
            hasUnresolvedResetCreditAttempt:
                store.hasUnresolvedResetCreditProtectionAttempt,
            requiresUpdateAttention: updateRequiresAttention
        )
    }

    private func visibilityResolution(
        for section: DashboardSection
    ) -> DashboardSectionVisibilityPolicy.Resolution {
        DashboardSectionVisibilityPolicy.resolve(
            section: section,
            preferredVisible:
                store.isDashboardSectionVisible(section),
            resetCreditStatus: store.resetCreditProtectionStatus,
            hasUnresolvedResetCreditAttempt:
                store.hasUnresolvedResetCreditProtectionAttempt,
            requiresUpdateAttention: updateRequiresAttention
        )
    }

    private var modelIQDetailsExpansionBinding: Binding<Bool> {
        disclosureExpansionBinding(
            for: .modelIQDetails,
            forcedExpanded: DashboardVisualTestOverrides.expandsModelIQ
        )
    }

    private var quotaHistoryExpansionBinding: Binding<Bool> {
        disclosureExpansionBinding(
            for: .quotaHistory,
            forcedExpanded:
                DashboardVisualTestOverrides.expandsQuotaHistory
        )
    }

    private var radarInsightsDetailsExpansionBinding: Binding<Bool> {
        disclosureExpansionBinding(
            for: .radarInsightsDetails,
            forcedExpanded:
                DashboardVisualTestOverrides.expandsSecondarySections
        )
    }

    private func storedDisclosureExpansionBinding(
        for disclosure: DashboardDisclosure
    ) -> Binding<Bool> {
        Binding(
            get: {
                store.isDashboardDisclosureExpanded(disclosure)
            },
            set: { expanded in
                store.setDashboardDisclosure(
                    disclosure,
                    expanded: expanded
                )
            }
        )
    }

    private func storedDisclosureVisibilityBinding(
        for disclosure: DashboardDisclosure
    ) -> Binding<Bool> {
        Binding(
            get: {
                store.isDashboardDisclosureVisible(disclosure)
            },
            set: { visible in
                store.setDashboardDisclosure(
                    disclosure,
                    visible: visible
                )
            }
        )
    }

    private func disclosureExpansionBinding(
        for disclosure: DashboardDisclosure,
        forcedExpanded: Bool
    ) -> Binding<Bool> {
        Binding(
            get: {
                forcedExpanded
                    || store.isDashboardDisclosureExpanded(disclosure)
            },
            set: { expanded in
                store.setDashboardDisclosure(
                    disclosure,
                    expanded: expanded
                )
            }
        )
    }

    private var toolbarContent: some View {
        VStack(spacing: 0) {
            if !customizesLayout && !store.layoutDiscoveryTipDismissed {
                layoutDiscoveryTip
                    .padding(.horizontal, Layout.contentPadding)
                    .padding(.top, 8)
            }
            actionButtons
                .padding(.horizontal, Layout.contentPadding)
                .padding(.vertical, 8)
        }
    }

    private var layoutDiscoveryTip: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    setLayoutEditorVisible(true)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.3.group")
                        .foregroundStyle(Color.accentColor)
                    Text(text(
                        "排序、显示与默认展开都能调整",
                        "Reorder, show, or set defaults"
                    ))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    Spacer(minLength: 4)
                    Text(text("试试布局", "Try Layout"))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(
                            size: metrics.caption,
                            weight: .semibold
                        ))
                        .foregroundStyle(Color.accentColor)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(text(
                "打开布局编辑器，调整模块顺序、显示和默认展开",
                "Open Layout to reorder, show or hide, and set defaults"
            ))

            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    store.dismissLayoutDiscoveryTip()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(
                        size: metrics.caption,
                        weight: .semibold
                    ))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(text("关闭布局提示", "Dismiss Layout tip"))
            .accessibilityLabel(text(
                "不再显示布局提示",
                "Do not show the Layout tip again"
            ))
        }
        .font(.system(size: metrics.caption))
        .padding(.leading, 9)
        .padding(.trailing, 6)
        .padding(.vertical, 7)
        .background(
            Color.accentColor.opacity(0.08),
            in: RoundedRectangle(cornerRadius: Layout.toolbarCornerRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Layout.toolbarCornerRadius)
                .stroke(Color.accentColor.opacity(0.16))
        }
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
                    .minimumScaleFactor(0.82)
                Text(headerDetailText)
                    .font(.system(size: metrics.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
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
        collapsibleSection(
            isExpanded: renderedExpansionBinding(for: .menuBarGuide),
            systemImage: "menubar.rectangle",
            title: text("状态栏说明", "Menu bar guide"),
            trailing: menuBarTitle
        ) {
            VStack(alignment: .leading, spacing: 7) {
                expandableCaptionText(
                    statusLegendDescription,
                    key: "status-legend",
                    collapsedLines: 2
                )
                HStack(spacing: 6) {
                    legendTile(metric: .weeklyQuota, color: quotaColor)
                    if hasLocalShortQuota {
                        legendTile(metric: .shortQuota, color: shortQuotaColor)
                    }
                    legendTile(metric: .quotaPace, color: quotaPaceColor)
                    legendTile(metric: .codexIQ, color: iqColor)
                    legendTile(metric: .signal, color: signalColor)
                }
            }
        }
    }

    private var hasLocalShortQuota: Bool {
        state.rateLimits?.shortBucket != nil
    }

    private var statusLegendDescription: String {
        if hasLocalShortQuota {
            return text(
                "默认显示“周额度 / IQ / 质量”；可打开 5h 和应剩。",
                "Default: Weekly / IQ / Quality; enable 5h and Pace when useful."
            )
        }
        return text(
            "默认显示“周额度 / IQ / 质量”；5h 当前暂停，已自动隐藏；可打开应剩。",
            "Default: Weekly / IQ / Quality. The 5h window is currently paused and hidden automatically; Pace remains optional."
        )
    }

    private var quotaSection: some View {
        collapsibleSection(
            isExpanded: renderedExpansionBinding(for: .quota),
            systemImage: DashboardSection.quota.systemImage,
            title: DashboardSection.quota.label(language: language),
            trailing: DisplayFormatters.percent(
                state.rateLimits?.weeklyRemainingPercent
            )
        ) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: Layout.tileSpacing) {
                    quotaTile(
                        title: text("周额度", "Weekly"),
                        value: DisplayFormatters.percent(
                            state.rateLimits?.weeklyRemainingPercent
                        ),
                        resetAt: state.rateLimits?.weeklyBucket?.resetsAt
                    )
                    if hasLocalShortQuota {
                        quotaTile(
                            title: text("短窗", "Short"),
                            value: DisplayFormatters.percent(
                                state.rateLimits?.shortRemainingPercent
                            ),
                            resetAt: state.rateLimits?.shortBucket?.resetsAt
                        )
                    }
                }
                if let planType = state.rateLimits?.snapshot.planType {
                    Text("\(text("套餐", "Plan")) \(planType)")
                        .font(.system(size: metrics.caption))
                        .foregroundStyle(.secondary)
                }
                if store.isDashboardDisclosureVisible(.quotaHistory) {
                    quotaHistorySection
                }
            }
        }
    }

    private var quotaHistorySection: some View {
        collapsibleSection(
            isExpanded: quotaHistoryExpansionBinding,
            systemImage: DashboardDisclosure.quotaHistory.systemImage,
            title: DashboardDisclosure.quotaHistory.label(
                language: language
            ),
            trailing: quotaHistoryRangeLabel(store.quotaHistoryRange)
        ) {
            QuotaHistoryChartView(
                timeline: store.displayedQuotaHistory,
                range: $store.quotaHistoryRange,
                endingAt: store.quotaHistoryDisplayNow,
                language: language,
                metrics: metrics,
                storageUnavailable:
                    store.quotaHistoryStorageUnavailable
            )
        }
    }

    private func quotaHistoryRangeLabel(
        _ range: QuotaHistoryRange
    ) -> String {
        switch range {
        case .hours24:
            return text("24 小时", "24 hours")
        case .days7:
            return text("7 天", "7 days")
        case .days30:
            return text("30 天", "30 days")
        }
    }

    private var quotaPacingSection: some View {
        let pacing = state.rateLimits?.quotaPacing(
            strategy: store.quotaPacingStrategy,
            holidayCalendar: store.quotaPacingHolidayCalendar
        )
        return collapsibleSection(
            isExpanded: renderedExpansionBinding(for: .usagePace),
            systemImage: DashboardSection.usagePace.systemImage,
            title: DashboardSection.usagePace.label(language: language),
            trailing: pacing.map {
                text(
                    "建议 \(DisplayFormatters.percent($0.roundedTargetRemainingPercent))",
                    "Target \(DisplayFormatters.percent($0.roundedTargetRemainingPercent))"
                )
            }
        ) {
            VStack(alignment: .leading, spacing: 7) {
                if let pacing {
                    HStack(spacing: Layout.tileSpacing) {
                        pacingTile(
                            title: text("建议剩余", "Target left"),
                            value: DisplayFormatters.percent(
                                pacing.roundedTargetRemainingPercent
                            ),
                            detail: quotaPacingStrategyLabel(pacing.strategy),
                            color: quotaPaceColor
                        )
                        pacingTile(
                            title: text("实际剩余", "Actual left"),
                            value: DisplayFormatters.percent(
                                pacing.roundedCurrentRemainingPercent
                            ),
                            detail: text("本机周额度", "local weekly"),
                            color: .primary
                        )
                        pacingTile(
                            title: quotaPacingDeltaTitle(pacing),
                            value: quotaPacingDeltaValue(pacing),
                            detail: quotaPacingDeltaDetail(pacing),
                            color: quotaPaceColor
                        )
                    }
                    expandableCaptionText(
                        quotaPacingExplanation(pacing),
                        key: "quota-pacing-explanation-\(pacing.strategy.rawValue)-\(pacing.roundedTargetRemainingPercent)-\(pacing.roundedCurrentRemainingPercent)",
                        collapsedLines: 3
                    )
                } else {
                    expandableCaptionText(
                        text(
                            "还没有读取到周额度 reset 时间，暂时无法计算建议剩余。",
                            "Weekly reset timing is not loaded yet, so the target remaining quota is unavailable."
                        ),
                        key: "quota-pacing-unavailable",
                        collapsedLines: 2
                    )
                }
            }
        }
    }

    private var radarSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("CodexRadar", systemImage: "dot.radiowaves.left.and.right")
            expandableMenuText(
                radarTitle,
                key: "codex-radar-title-\(radarTitle)",
                collapsedLines: 2,
                fontSize: metrics.body,
                weight: .medium,
                color: .primary
            )
            HStack {
                labelPair(text("当前重点", "Focus"), radarFocus)
                Spacer()
                labelPair(text("旧提醒", "Legacy alerts"), radarLegacyStatus)
            }
            expandableMenuText(
                radarSummary,
                key: "codex-radar-summary-\(radarFocus)-\(radarLegacyStatus)",
                collapsedLines: 2,
                fontSize: metrics.label
            )
        }
    }

    @ViewBuilder
    private var siteAnnouncementSection: some View {
        if let announcement = state.current?.siteAnnouncement,
           let message = announcement.message?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    sectionTitle(text("CodexRadar 公告", "CodexRadar Notice"), systemImage: "megaphone")
                    Spacer(minLength: 8)
                    if let updatedLabel = announcement.updatedLabel, !updatedLabel.isEmpty {
                        Text(updatedLabel)
                            .font(.system(size: metrics.caption, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }
                expandableCaptionText(
                    message,
                    key: "site-announcement-\(announcement.updatedLabel ?? "")-\(message)",
                    collapsedLines: 2
                )
                if let sourceURL = announcement.sourceURL.flatMap(URL.init(string:)) {
                    Button {
                        store.openURL(sourceURL)
                    } label: {
                        Label(
                            announcement.sourceLabel ?? text("查看来源", "Open source"),
                            systemImage: "arrow.up.right.square"
                        )
                        .font(.system(size: metrics.caption, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help(text("打开公告来源", "Open announcement source"))
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var codexRadarCommunitySection: some View {
        let cards = codexRadarCommunityCards
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                sectionTitle(text("CodexRadar 社区知识", "CodexRadar Community"), systemImage: "lightbulb")
                ForEach(Array(cards.prefix(3).enumerated()), id: \.offset) { index, card in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.title ?? text("社区知识", "Community note"))
                            .font(.system(size: metrics.body, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        if let prompt = card.prompt?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !prompt.isEmpty {
                            expandableCaptionText(
                                prompt,
                                key: "codexradar-community-\(index)-\(card.title ?? "")",
                                collapsedLines: 3
                            )
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    @ViewBuilder
    private var resetJudgementSection: some View {
        if let judgement = state.current?.resetJudgement,
           !judgement.cards.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                sectionTitle(text("CodexRadar 重置雷达", "CodexRadar Reset Radar"), systemImage: "arrow.clockwise.circle")
                HStack(alignment: .firstTextBaseline) {
                    Text(judgement.title ?? text("重置雷达研判", "Reset judgement"))
                        .font(.system(size: metrics.body, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Spacer(minLength: 8)
                    Text(judgement.updatedLabel ?? "")
                        .font(.system(size: metrics.caption, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                HStack(spacing: Layout.tileSpacing) {
                    ForEach(judgement.cards.prefix(2)) { card in
                        resetJudgementCard(card)
                    }
                }
                if !judgement.reasons.isEmpty {
                    expandableCaptionText(
                        resetJudgementReasonsText(judgement),
                        key: "reset-judgement-reasons-\(judgement.title ?? "")-\(judgement.updatedLabel ?? "")",
                        collapsedLines: 3
                    )
                }
            }
        }
    }

    private var communityKnowledgeSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(resetCreditCommunityKnowledge?.title ?? text("重置卡过期时间自查", "Reset credit expiry check"))
                .font(.system(size: metrics.body, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            expandableCaptionText(
                text(
                    "默认低频自动刷新 reset credits；只读取本机 Codex 登录态，不保存 token，只缓存下方脱敏结果。",
                    "Low-frequency auto refresh is on by default. It reads local Codex auth, never stores tokens, and only caches the sanitized result below."
                ),
                key: "reset-credit-intro",
                collapsedLines: 3
            )

            resetCreditStatusContent

            VStack(alignment: .leading, spacing: 4) {
                Toggle(text("自动查询重置卡", "Auto check credits"), isOn: $store.resetCreditAutoRefreshEnabled)
                    .toggleStyle(.checkbox)
                    .font(.system(size: metrics.label, weight: .medium))
                expandableCaptionText(
                    text(
                        "启动后和缓存超过 6 小时时自动刷新；失败不弹通知、不影响状态栏，旧缓存会继续保留。",
                        "Refreshes after launch and when the cache is older than 6 hours. Failures stay quiet, keep old cache, and do not affect the menu bar."
                    ),
                    key: "reset-credit-auto-description",
                    collapsedLines: 3
                )
            }

            resetCreditProtectionControls

            HStack(spacing: Layout.tileSpacing) {
                compactActionButton(
                    title: resetCreditRefreshButtonTitle,
                    systemImage: store.resetCreditPhase.isLoading ? "hourglass" : "arrow.clockwise"
                ) {
                    store.refreshResetCredits()
                }
                compactActionButton(
                    title: copiedCommunityPrompt ? text("已复制", "Copied") : text("复制 Prompt", "Copy Prompt"),
                    systemImage: copiedCommunityPrompt ? "checkmark.circle" : "doc.on.clipboard"
                ) {
                    copyCommunityPrompt(resetCreditPrompt)
                }
                compactActionButton(title: "Codex", systemImage: "terminal") {
                    store.openCodexApp()
                }
            }
        }
    }

    private var resetCreditSection: some View {
        collapsibleSection(
            isExpanded: renderedExpansionBinding(for: .resetCredits),
            systemImage: "creditcard",
            title: text("重置卡与自动使用", "Reset credits & auto-use"),
            trailing: resetCreditSectionSummary,
            isExpansionLocked: forcesResetCreditSectionExpansion
        ) {
            communityKnowledgeSection
        }
    }

    private var forcesResetCreditSectionExpansion: Bool {
        DashboardSectionExpansionPolicy.forcesExpansion(
            of: .resetCredits,
            resetCreditStatus: store.resetCreditProtectionStatus,
            hasUnresolvedResetCreditAttempt:
                store.hasUnresolvedResetCreditProtectionAttempt
        )
    }

    private var resetCreditSectionSummary: String {
        switch store.resetCreditProtectionStatus {
        case .enabling, .checking:
            return text("检查中", "Checking")
        case .scheduled:
            return text("已排期", "Scheduled")
        case .waitingForUsage:
            return text("等待可重置额度", "Waiting for usage")
        case .using:
            return text("正在使用", "Using")
        case .reconciling:
            return text("正在对账", "Reconciling")
        case .succeeded:
            return text("已使用", "Used")
        case .blocked, .missed:
            return text("需要处理", "Needs attention")
        case .noCredits, .previewNoCredits:
            return text("暂无可用卡", "No available credits")
        case .preview(_, _, let availableCount, _):
            return text("\(availableCount) 张可用", "\(availableCount) available")
        case .unavailable:
            return text("已不可用", "Unavailable")
        case .disabled:
            if let count = store.resetCreditSnapshot?.effectiveAvailableCount {
                return count > 0
                    ? text("\(count) 张可用 · 自动使用关", "\(count) available · auto-use off")
                    : text("暂无可用卡 · 自动使用关", "No credits · auto-use off")
            }
            return text("自动使用关", "Auto-use off")
        }
    }

    private var codexRadarDetailsSection: some View {
        collapsibleSection(
            isExpanded: renderedExpansionBinding(for: .radarDetails),
            systemImage: "dot.radiowaves.left.and.right",
            title: text("更多 CodexRadar 信息", "More from CodexRadar"),
            trailing: text("公告、社区与雷达", "Notice, community & radar")
        ) {
            VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                siteAnnouncementSection
                codexRadarCommunitySection
                resetJudgementSection
                codexRadarQuotaSection
                codexRadarFastSection
                radarSection
                if showsPredictionSection {
                    predictionSection
                }
            }
        }
    }

    private var resetCreditProtectionControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(
                text("重置卡到期前自动使用", "Auto-use reset credits before expiry"),
                isOn: Binding(
                    get: { store.resetCreditProtectionEnabled },
                    set: { enabled in
                        if enabled {
                            showsResetCreditProtectionConfirmation = true
                        } else {
                            showsResetCreditProtectionConfirmation = false
                            store.disableResetCreditExpiryProtection()
                        }
                    }
                )
            )
            .toggleStyle(.checkbox)
            .font(.system(size: metrics.label, weight: .semibold))
            .disabled(
                !store.resetCreditProtectionEnabled
                    && (
                        store.resetCreditProtectionStatus.isBusy
                            || isResetCreditProtectionOffWithUnresolvedAttempt
                    )
            )

            expandableCaptionText(
                text(
                    "默认关闭。开启后，App 会在最早一张受支持的重置卡到期前约 30 分钟自动尝试使用。开启时会用新的 Codex 会话核对登录邮箱和完整明细，并只授权当时可见的卡；是否有可重置额度仍由服务端判断。",
                    "Off by default. When enabled, the app automatically attempts to use the earliest supported reset credit about 30 minutes before it expires. A fresh Codex session verifies the login email and complete details, authorizing only the credits visible at that moment; the server still decides whether any usage can be reset."
                ),
                key: "reset-credit-protection-description",
                collapsedLines: 4
            )

            if showsResetCreditProtectionConfirmation,
               !isResetCreditProtectionOffWithUnresolvedAttempt {
                VStack(alignment: .leading, spacing: 6) {
                    Text(text("确认开启自动使用", "Confirm automatic use"))
                        .font(.system(size: metrics.caption, weight: .semibold))
                        .foregroundStyle(.orange)
                    expandableCaptionText(
                        text(
                            "条件满足时会真实尝试使用一张已确认授权的重置卡；成功后不可撤销，关闭也无法召回已经写出的请求。每次尝试前会用新的 Codex 会话复核登录邮箱、完整明细和精确卡片；若检测到退出、不同邮箱、未授权新卡或无法证明系统时间连续，会在写请求前关闭。App 必须保持运行联网；关机或没有可重置额度仍可能失败。",
                            "When conditions are met, the app actually attempts to use one explicitly authorized credit. Success is irreversible, and turning auto-use off cannot recall a request already written. Before every attempt, a fresh Codex session rechecks the login email, complete details, and exact credit; sign-out, a different email, an unapproved new credit, or unprovable clock continuity turns auto-use off before the write. The app must stay running and online; shutdown or no resettable usage can still prevent redemption."
                        ),
                        key: "reset-credit-protection-confirmation",
                        collapsedLines: 6
                    )
                    HStack(spacing: Layout.tileSpacing) {
                        compactActionButton(
                            title: text("开启自动使用", "Enable auto-use"),
                            systemImage: "checkmark.shield"
                        ) {
                            showsResetCreditProtectionConfirmation = false
                            store.enableResetCreditExpiryProtection()
                        }
                        compactActionButton(
                            title: text("取消", "Cancel"),
                            systemImage: "xmark"
                        ) {
                            showsResetCreditProtectionConfirmation = false
                        }
                    }
                }
                .padding(8)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            if !store.resetCreditProtectionEnabled,
               (
                   !showsResetCreditProtectionConfirmation
                       || isResetCreditProtectionOffWithUnresolvedAttempt
               ) {
                if isResetCreditProtectionOffWithUnresolvedAttempt {
                    compactActionButton(
                        title: text("立即只读对账", "Reconcile now (read only)"),
                        systemImage: store.resetCreditProtectionStatus.isBusy
                            ? "hourglass"
                            : "arrow.triangle.2.circlepath"
                    ) {
                        store.refreshNow()
                    }
                    .disabled(store.resetCreditProtectionStatus.isBusy)
                } else {
                    compactActionButton(
                        title: text("只读检查自动使用计划", "Preview auto-use (read only)"),
                        systemImage: store.resetCreditProtectionStatus.isBusy
                            ? "hourglass"
                            : "checkmark.shield"
                    ) {
                        store.previewResetCreditExpiryProtectionPlan()
                    }
                    .disabled(store.resetCreditProtectionStatus.isBusy)
                }
            }

            resetCreditProtectionStatusView
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .onChange(of: store.hasUnresolvedResetCreditProtectionAttempt) {
            if $0 {
                showsResetCreditProtectionConfirmation = false
            }
        }
    }

    private var isResetCreditProtectionOffWithUnresolvedAttempt: Bool {
        !store.resetCreditProtectionEnabled
            && store.hasUnresolvedResetCreditProtectionAttempt
    }

    private var resetCreditProtectionStatusView: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(resetCreditProtectionStatusTitle)
                .font(.system(size: metrics.caption, weight: .semibold))
                .foregroundStyle(resetCreditProtectionStatusColor)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = resetCreditProtectionStatusDetail {
                expandableCaptionText(
                    detail,
                    key: "reset-credit-protection-status-\(String(describing: store.resetCreditProtectionStatus))",
                    collapsedLines: 4
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resetCreditProtectionStatusTitle: String {
        switch store.resetCreditProtectionStatus {
        case .disabled:
            return text("未开启，不会自动使用任何卡", "Off; no credit will be used automatically")
        case .enabling:
            return text("正在只读核对账号与重置卡…", "Checking the account and credits without using one…")
        case .checking:
            return text("正在执行使用前只读检查…", "Running the read-only preflight…")
        case .noCredits:
            return text("已开启 · 当前没有可用重置卡", "On · no reset credits are currently available")
        case .preview(_, _, _, let readyNow):
            return readyNow
                ? text("只读检查完成 · 已接近到期", "Read-only check complete · near expiry")
                : text("只读检查完成 · 可以排期", "Read-only check complete · ready to schedule")
        case .previewNoCredits:
            return text("只读检查完成 · 当前没有可用重置卡", "Read-only check complete · no credits available")
        case .scheduled(let actionAt, _, _):
            return text(
                "已开启 · 计划 \(DisplayFormatters.compactDateTime(actionAt)) 尝试",
                "On · attempt scheduled for \(DisplayFormatters.compactDateTime(actionAt))"
            )
        case .waitingForUsage:
            return text("已接近到期 · 等待出现可重置额度", "Near expiry · waiting for eligible usage")
        case .using:
            return text("正在请求 Codex 使用重置卡…", "Asking Codex to use the reset credit…")
        case .reconciling:
            return store.resetCreditProtectionEnabled
                ? text("正在与 Codex 对账使用结果…", "Reconciling the result with Codex…")
                : text(
                    "自动使用已关闭 · 上次请求仅做只读对账",
                    "Auto-use off · prior request stays read only"
                )
        case .succeeded:
            return text("已验证该卡已使用", "Verified credit is used")
        case .unavailable:
            return text("卡已不再可用", "The credit is no longer available")
        case .missed:
            return text("未能在过期前确认使用", "Usage was not confirmed before expiry")
        case .blocked(let reason, _):
            if isResetCreditProtectionOffWithUnresolvedAttempt {
                return text(
                    "自动使用已关闭 · 上次请求结果仍未确认",
                    "Auto-use off · prior request remains unresolved"
                )
            }
            if case .clockChanged = reason {
                return text(
                    "到期前自动使用已关闭 · 需重新确认",
                    "Auto-use before expiry turned off · confirmation required"
                )
            }
            return text("到期前自动使用暂时受阻", "Auto-use before expiry is blocked")
        }
    }

    private var resetCreditProtectionStatusDetail: String? {
        switch store.resetCreditProtectionStatus {
        case .disabled:
            return text(
                "普通过期时间查询仍可单独使用。",
                "The regular expiry-time check remains available."
            )
        case .enabling, .checking, .using:
            return nil
        case .noCredits(let checkedAt):
            return text(
                "最近检查 \(DisplayFormatters.compactDateTime(checkedAt))；保持开启后会继续只读检查。",
                "Last checked \(DisplayFormatters.compactDateTime(checkedAt)); read-only checks continue while enabled."
            )
        case .preview(let actionAt, let expiresAt, let availableCount, let readyNow):
            if readyNow {
                return text(
                    "服务端 \(availableCount) 张可用卡的明细完整；下一张 \(DisplayFormatters.compactDateTime(expiresAt)) 到期。现在开启后可能立即真实使用。",
                    "Details are complete for \(availableCount) available credit(s); the next expires \(DisplayFormatters.compactDateTime(expiresAt)). Enabling now may trigger real usage immediately."
                )
            }
            return text(
                "服务端 \(availableCount) 张可用卡的明细完整；如果开启，预计 \(DisplayFormatters.compactDateTime(actionAt)) 尝试使用，卡片 \(DisplayFormatters.compactDateTime(expiresAt)) 到期。本次检查没有消费。",
                "Details are complete for \(availableCount) available credit(s). If enabled, usage is planned for \(DisplayFormatters.compactDateTime(actionAt)); the credit expires \(DisplayFormatters.compactDateTime(expiresAt)). This check consumed nothing."
            )
        case .previewNoCredits(let checkedAt):
            return text(
                "检查于 \(DisplayFormatters.compactDateTime(checkedAt)) 完成，本次没有消费。",
                "Checked at \(DisplayFormatters.compactDateTime(checkedAt)); nothing was consumed."
            )
        case .scheduled(_, let expiresAt, let availableCount):
            return text(
                "服务端明细完整，共 \(availableCount) 张可用卡；下一张到期 \(DisplayFormatters.compactDateTime(expiresAt))。登录时启动能降低错过风险。",
                "Server details are complete for \(availableCount) available credit(s). The next expires \(DisplayFormatters.compactDateTime(expiresAt)). Launch at login reduces the chance of missing it."
            )
        case .waitingForUsage(let expiresAt):
            return text(
                "下一张卡将在 \(DisplayFormatters.compactDateTime(expiresAt)) 到期。当前尚未出现需要重置的额度，App 会继续检查至到期；能否最终使用仍取决于运行、网络和 Codex 状态。",
                "The next credit expires \(DisplayFormatters.compactDateTime(expiresAt)). No limit currently needs a reset. The app keeps checking until expiry; eventual use still depends on runtime, network, and Codex state."
            )
        case .reconciling(let expiresAt):
            if store.resetCreditProtectionEnabled {
                return text(
                    "下一张卡到期 \(DisplayFormatters.compactDateTime(expiresAt))。结果不明确时先只读对账；只有仍需重试时，才会用原幂等键重试同一张卡，绝不换卡。",
                    "The credit expires \(DisplayFormatters.compactDateTime(expiresAt)). Ambiguous results are reconciled read only first. Only if a retry is still needed can the same credit be retried with its original idempotency key; Sentinel never switches credits."
                )
            }
            return text(
                "上次请求结果仍未确认；卡片到期 \(DisplayFormatters.compactDateTime(expiresAt))。自动使用已关闭，只会只读对账，不会重试或换卡。为避免重复请求，确认结果前不能重新开启；可点“立即只读对账”主动复核。",
                "The prior request is still unresolved; the credit expires \(DisplayFormatters.compactDateTime(expiresAt)). Auto-use is off, so Sentinel only reconciles read only and will not retry or switch credits. To avoid a duplicate request, auto-use cannot be re-enabled until the result is known. Use “Reconcile now (read only)” to check again."
            )
        case .succeeded(let usedAt, _):
            return text(
                "Codex 已确认该卡处于已使用状态，并已读取最新额度；确认于 \(DisplayFormatters.compactDateTime(usedAt))。",
                "Codex confirmed that the credit is in the used state; latest limits were read at \(DisplayFormatters.compactDateTime(usedAt))."
            )
        case .unavailable(let checkedAt, _):
            return text(
                "最近确认 \(DisplayFormatters.compactDateTime(checkedAt))。可能由你在其他位置使用；Sentinel 不会冒充自己成功。",
                "Confirmed \(DisplayFormatters.compactDateTime(checkedAt)). It may have been used elsewhere; Sentinel does not claim the action as its own."
            )
        case .missed(let expiresAt):
            return text(
                "到期时间 \(DisplayFormatters.compactDateTime(expiresAt))。请检查 App 是否运行、网络和 Codex 登录态。",
                "It expired \(DisplayFormatters.compactDateTime(expiresAt)). Check that the app was running, online, and signed in to Codex."
            )
        case .blocked(let reason, let detail):
            let blockMessage = resetCreditProtectionBlockMessage(
                reason,
                detail: detail
            )
            guard isResetCreditProtectionOffWithUnresolvedAttempt else {
                return blockMessage
            }
            return text(
                "上次请求结果仍未确认。自动使用已关闭，只会只读对账，绝不重试或换卡；为避免重复请求，确认结果前不能重新开启。可点“立即只读对账”主动复核。",
                "The prior request remains unresolved. Auto-use is off, so reconciliation is read only and never retries or switches credits. To avoid a duplicate request, auto-use cannot be re-enabled until the result is known. Use “Reconcile now (read only)” to check again."
            ) + "\n" + blockMessage
        }
    }

    private var resetCreditProtectionStatusColor: Color {
        switch store.resetCreditProtectionStatus {
        case .succeeded, .scheduled, .noCredits, .preview, .previewNoCredits:
            return .green
        case .enabling, .checking, .using, .reconciling, .waitingForUsage:
            return .orange
        case .blocked, .missed:
            return .red
        case .disabled, .unavailable:
            return .secondary
        }
    }

    private func resetCreditProtectionBlockMessage(
        _ reason: ResetCreditProtectionStatus.BlockReason,
        detail: String?
    ) -> String {
        switch reason {
        case .accountIdentityUnavailable:
            return text(
                "Codex 没有提供可稳定绑定的 ChatGPT 账号身份，因此保持关闭。请确认使用 ChatGPT 账号登录。",
                "Codex did not provide a stable ChatGPT account identity, so auto-use remains off. Confirm that Codex is signed in with ChatGPT."
            )
        case .accountChanged:
            return text(
                "Codex 账号已变化，到期前自动使用已关闭。若存在未决尝试，切回原账号后会先对账；否则可核对账号后重新显式开启。",
                "The Codex account changed, so auto-use before expiry was turned off. If an attempt is unresolved, switch back to the original account for reconciliation; otherwise verify the account and explicitly enable auto-use again."
            )
        case .detailsUnavailable(let availableCount):
            return text(
                "Codex 未返回可安全选卡的完整明细；当前已知可用数量为 \(availableCount)。不会盲目使用。",
                "Codex did not return complete details for safe credit selection; the known available count is \(availableCount). Nothing will be used blindly."
            )
        case .detailsIncomplete(let availableCount, let availableDetails):
            return text(
                "Codex 显示 \(availableCount) 张可用卡，但只提供 \(availableDetails) 张唯一明细；覆盖不完整，不会自动使用。",
                "Codex reports \(availableCount) available credit(s) but only \(availableDetails) unique detail row(s). Coverage is incomplete, so no automatic use occurs."
            )
        case .noSupportedExpiringCredits(let availableCount):
            return text(
                "当前 \(availableCount) 张卡里没有同时满足“可用、Codex 重置类型、有明确过期时间”的卡。",
                "None of the \(availableCount) credit(s) is simultaneously available, a supported Codex reset, and explicitly expiring."
            )
        case .codexUnavailable:
            return text(
                "没有找到可用的 Codex app-server。请安装或更新 Codex，然后重试。",
                "A usable Codex app-server was not found. Install or update Codex, then try again."
            )
        case .signedOut:
            return text(
                "Codex 当前没有可用的 ChatGPT 登录态。重新登录后会继续只读检查。",
                "Codex does not currently have usable ChatGPT authentication. Read-only checks resume after sign-in."
            )
        case .unsupportedCodex:
            return text(
                "当前 Codex 版本不支持官方重置卡消费 RPC；自动使用已关闭。更新 Codex 后请重新开启。",
                "This Codex version does not support the official reset-credit RPC, so auto-use was turned off. Update Codex and enable it again."
            )
        case .anotherProcess:
            return text(
                "另一个 Codex Radar 进程正在处理同一账号。当前进程不会并发使用卡，稍后会重试。",
                "Another Codex Radar process is handling this account. This process will not use a credit concurrently and will retry later."
            )
        case .journalUnavailable:
            return text(
                "本地自动使用记录无法可靠读取或写入。为避免重复使用，自动使用已关闭且不会发送请求；请更新 App 或联系维护者检查 Application Support 中的安全记录。",
                "The local auto-use record cannot be read or written reliably. Auto-use is off and no request will be sent to avoid duplicate use; update the app or ask the maintainer to inspect its Application Support safety record."
            )
        case .creditNotAuthorized:
            return text(
                "当前受支持卡片集合或最早到期目标已不同于本次显式授权，自动使用已关闭且不会发送请求。先做只读检查，再重新开启以确认当前可见卡片。",
                "The current supported-credit set or earliest target no longer matches this explicit authorization. Auto-use is off and no request will be sent. Run the read-only check, then enable again to confirm the currently visible credits."
            )
        case .clockChanged:
            return detail ?? text(
                "已确认系统计时连续性失效：墙钟相对连续计时的偏差已超出安全容差，或连续计时已重置（通常由 Mac 重启造成）。到期前自动使用已关闭且不会发送新请求；核对 Mac 时间与只读计划后再显式确认。普通 App 退出重开本身不会触发此状态。",
                "Clock continuity is confirmed lost: wall time diverged from continuous time beyond the safe tolerance, or continuous time reset (usually because the Mac restarted). Auto-use before expiry was turned off and no new request will be sent. Verify the Mac clock and read-only plan, then explicitly confirm again. Relaunching the app within the same boot does not cause this state by itself."
            )
        case .requestFailed:
            return detail ?? text(
                "Codex 请求暂时失败。不会根据不确定结果换用另一张卡。",
                "The Codex request failed. Sentinel will not switch to another credit based on an uncertain result."
            )
        }
    }

    @ViewBuilder
    private var resetCreditStatusContent: some View {
        if case .loading(_, let automatic) = store.resetCreditPhase {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                expandableMenuText(
                    text(
                        automatic
                            ? "正在自动刷新重置卡过期时间..."
                            : "正在读取本机 Codex 登录态，并请求 ChatGPT reset credits...",
                        automatic
                            ? "Auto-refreshing reset credit expiry..."
                            : "Reading local Codex auth and requesting ChatGPT reset credits..."
                    ),
                    key: "reset-credit-loading-\(automatic)",
                    collapsedLines: 2,
                    fontSize: metrics.caption,
                    weight: .medium
                )
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }

        if case .failed(let failure) = store.resetCreditPhase {
            resetCreditFailureView(failure)
        }

        if let snapshot = store.resetCreditSnapshot {
            resetCreditSnapshotView(snapshot)
        } else if !store.resetCreditPhase.isLoading {
            expandableCaptionText(
                text(
                    store.resetCreditAutoRefreshEnabled
                        ? "还没有缓存结果。自动查询会在启动后尝试一次，也可以点“立即刷新”。"
                        : "还没有缓存结果。打开自动查询或点“立即刷新”后，这里会显示每张卡的发放时间、过期时间和剩余时间。",
                    store.resetCreditAutoRefreshEnabled
                        ? "No cached result yet. Auto check will try after launch, or click Refresh now."
                        : "No cached result yet. Turn on auto check or click Refresh now to show issue time, expiry time, and time left."
                ),
                key: "reset-credit-empty-\(store.resetCreditAutoRefreshEnabled)",
                collapsedLines: 3
            )
        }
    }

    private func resetCreditFailureView(_ failure: ResetCreditFailure) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(resetCreditFailureTitle(failure))
                .font(.system(size: metrics.caption, weight: .semibold))
                .foregroundStyle(.red)
                .lineLimit(1)
            expandableCaptionText(
                resetCreditFailureMessage(failure),
                key: "reset-credit-failure-message-\(failure.kind)-\(failure.automatic)",
                collapsedLines: 3
            )
            expandableMenuText(
                resetCreditFailureRecovery(failure),
                key: "reset-credit-failure-recovery-\(failure.kind)-\(failure.automatic)",
                collapsedLines: 3,
                fontSize: metrics.caption,
                weight: .medium,
                color: .accentColor
            )
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func resetCreditFailureTitle(_ failure: ResetCreditFailure) -> String {
        if failure.automatic, store.resetCreditSnapshot != nil {
            return text("自动刷新失败，已保留上次结果", "Auto refresh failed; keeping last result")
        }
        if failure.automatic {
            return text("自动查询暂时失败", "Auto check failed for now")
        }
        return text("查询失败", "Check failed")
    }

    private func resetCreditFailureMessage(_ failure: ResetCreditFailure) -> String {
        switch failure.kind {
        case .authFileMissing:
            return text(
                "没有找到本机 Codex 登录文件，可能还没有在 Codex 里登录。",
                "Local Codex auth was not found. You may not be signed in to Codex yet."
            )
        case .invalidAuthFile:
            return text(
                "本机 Codex 登录文件不是可读取的 JSON。",
                "The local Codex auth file is not readable JSON."
            )
        case .accessTokenMissing:
            return text(
                "本机 Codex 登录文件里没有 access token。",
                "The local Codex auth file does not contain an access token."
            )
        case .unauthorized(let status):
            return text(
                "ChatGPT 拒绝了这次请求（HTTP \(status)），通常是登录态过期或账号态变化。",
                "ChatGPT rejected the request (HTTP \(status)), usually because the login state expired or the account state changed."
            )
        case .network:
            return text(
                "网络请求没有完成，可能是当前网络、代理或 ChatGPT 临时不可达。",
                "The network request did not finish. It may be the current network, proxy, or a temporary ChatGPT outage."
            )
        case .service(let status):
            return text(
                "ChatGPT reset credits 接口返回 HTTP \(status)。",
                "The ChatGPT reset credits endpoint returned HTTP \(status)."
            )
        case .responseChanged:
            return text(
                "接口返回内容和预期不一致，可能是 ChatGPT 调整了 reset credits 数据格式。",
                "The response did not match the expected shape. ChatGPT may have changed the reset credits format."
            )
        case .unknown:
            return text(
                "遇到未知错误：\(failure.detail)",
                "Unexpected error: \(failure.detail)"
            )
        }
    }

    private func resetCreditFailureRecovery(_ failure: ResetCreditFailure) -> String {
        switch failure.kind {
        case .authFileMissing, .invalidAuthFile, .accessTokenMissing:
            return text(
                "打开 Codex 并确认已登录，然后点“立即刷新”。",
                "Open Codex, confirm you are signed in, then click Refresh now."
            )
        case .unauthorized:
            return text(
                "重新登录 Codex 后再刷新；旧缓存不会被清掉。",
                "Sign in to Codex again, then refresh. The old cache is not cleared."
            )
        case .network, .service:
            return text(
                "稍后会自动重试，也可以现在手动刷新；这不会影响状态栏额度。",
                "It will retry later, or you can refresh now. This does not affect menu-bar quota."
            )
        case .responseChanged:
            return text(
                "可以先用“复制 Prompt”兜底查看；如果持续失败，说明需要适配新接口。",
                "Use Copy Prompt as a fallback for now. If it keeps failing, the app needs an endpoint update."
            )
        case .unknown:
            return text(
                "可以稍后重试；如果持续失败，复制错误信息到 issue 里更容易排查。",
                "Retry later. If it keeps failing, include this error in an issue for easier debugging."
            )
        }
    }

    private var codexRadarCommunityCards: [CommunityKnowledge] {
        let cards = state.current?.communityKnowledges ?? []
        let fallback = state.current?.communityKnowledge.map { [$0] } ?? []
        return (cards.isEmpty ? fallback : cards)
            .filter { !isResetCreditCommunityKnowledge($0) }
    }

    private var resetCreditCommunityKnowledge: CommunityKnowledge? {
        if let knowledge = (state.current?.communityKnowledges ?? [])
            .first(where: isResetCreditCommunityKnowledge) {
            return knowledge
        }
        if let knowledge = state.current?.communityKnowledge,
           isResetCreditCommunityKnowledge(knowledge) {
            return knowledge
        }
        return nil
    }

    private func isResetCreditCommunityKnowledge(_ knowledge: CommunityKnowledge) -> Bool {
        let body = "\(knowledge.title ?? "") \(knowledge.prompt ?? "")".lowercased()
        return body.contains("重置卡")
            || body.contains("reset credit")
            || body.contains("reset credits")
            || body.contains("rate-limit reset")
    }

    private var resetCreditPrompt: String {
        if let prompt = resetCreditCommunityKnowledge?.prompt,
           !prompt.isEmpty {
            return prompt
        }
        return text(
            "帮我用本机 Codex 凭证查一下 rate-limit reset credits，读取 ~/.codex/auth.json 里的 tokens.access_token，请求 https://chatgpt.com/backend-api/wham/rate-limit-reset-credits。要求：如果 401，说明是凭证失效或没带对 Authorization header；不要打印 access_token、refresh_token、cookie 或完整唯一 ID；只要展示每张重置卡发放时间和过期时间，从 UTC 转成北京时间，用中文回复。",
            "Use my local Codex credentials to check rate-limit reset credits from ~/.codex/auth.json tokens.access_token via https://chatgpt.com/backend-api/wham/rate-limit-reset-credits. If it returns 401, explain that the credential is expired or the Authorization header is missing. Do not print access_token, refresh_token, cookies, or full unique IDs. Show only each reset credit issue time and expiry time, converted to local time."
        )
    }

    private var resetCreditRefreshButtonTitle: String {
        store.resetCreditPhase.isLoading
            ? text("查询中", "Checking")
            : text("立即刷新", "Refresh now")
    }

    private var radarRecommendationGroups: [RadarRecommendationGroup] {
        (state.radarInsights?.recommendations ?? []).filter {
            !$0.validItems.isEmpty
        }
    }

    private var radarDegradationItems: [RadarDegradationAlert] {
        state.radarInsights?.degradationAlerts.validItems ?? []
    }

    @ViewBuilder
    private var codexRadarInsightsSection: some View {
        let groups = radarRecommendationGroups
        let alerts = radarDegradationItems
        if !groups.isEmpty || !alerts.isEmpty {
            collapsibleSection(
                isExpanded: renderedExpansionBinding(for: .insights),
                systemImage: DashboardSection.insights.systemImage,
                title: DashboardSection.insights.label(language: language),
                trailing: insightsSectionSummary(alerts: alerts)
            ) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: Layout.tileSpacing) {
                        radarInsightPickTile(groups)
                        radarInsightAlertTile(alerts)
                    }

                    if let updated = radarInsightsUpdatedLabel {
                        Text(updated)
                            .font(.system(size: metrics.caption, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    if store.isDashboardDisclosureVisible(
                        .radarInsightsDetails
                    ) {
                        collapsibleSection(
                            isExpanded:
                                radarInsightsDetailsExpansionBinding,
                            systemImage: "list.bullet.rectangle",
                            title: text("场景推荐与降智预警", "Recommendations and alerts"),
                            trailing: radarInsightsCountLabel(groups: groups, alerts: alerts)
                        ) {
                            VStack(alignment: .leading, spacing: 8) {
                                if !alerts.isEmpty {
                                    Text(text("降智预警", "Degradation alerts"))
                                        .font(.system(size: metrics.caption, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 5) {
                                        ForEach(
                                            Array(alerts.enumerated()),
                                            id: \.offset
                                        ) { _, alert in
                                            radarDegradationRow(alert)
                                        }
                                    }
                                    .padding(8)
                                    .background(
                                        Color.orange.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                                }

                                if !groups.isEmpty {
                                    Text(text("场景推荐", "Scenario recommendations"))
                                        .font(.system(size: metrics.caption, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    ForEach(
                                        Array(groups.enumerated()),
                                        id: \.offset
                                    ) { index, group in
                                        radarRecommendationCard(group, index: index)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func insightsSectionSummary(
        alerts: [RadarDegradationAlert]
    ) -> String {
        if alerts.isEmpty {
            return text("当前无预警", "No alerts")
        }
        return text(
            "\(alerts.count) 个预警",
            "\(alerts.count) \(alerts.count == 1 ? "alert" : "alerts")"
        )
    }

    private func radarInsightPickTile(
        _ groups: [RadarRecommendationGroup]
    ) -> some View {
        let dailyItem = preferredDailyRecommendation(in: groups)
        let item = dailyItem ?? groups.first?.validItems.first
        return VStack(alignment: .leading, spacing: 3) {
            Text(
                dailyItem == nil
                    ? text("推荐首选", "Top pick")
                    : text("日常开发首选", "Daily pick")
            )
                .font(.system(size: metrics.caption, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(item.map(radarModelEffortLabel) ?? text("暂无", "None"))
                .font(.system(size: metrics.body, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(
                item.map {
                    "IQ \(DisplayFormatters.iqScore($0.iq)) · \(DisplayFormatters.costUSD($0.averageCostUSD))"
                } ?? text("等待推荐数据", "Waiting for data")
            )
            .font(.system(size: metrics.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.68)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    private func radarInsightAlertTile(
        _ alerts: [RadarDegradationAlert]
    ) -> some View {
        let top = alerts.max {
            $0.largestDrop < $1.largestDrop
        }
        return VStack(alignment: .leading, spacing: 3) {
            Text(text("降智预警", "IQ alerts"))
                .font(.system(size: metrics.caption, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(
                alerts.isEmpty
                    ? text("当前无", "None")
                    : text(
                        "\(alerts.count) 个档位",
                        "\(alerts.count) \(alerts.count == 1 ? "config" : "configs")"
                    )
            )
            .font(.system(size: metrics.body, weight: .semibold))
            .foregroundStyle(alerts.isEmpty ? Color.green : Color.orange)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            Text(
                top.map {
                    "\(radarModelEffortLabel($0)) · ↓\(radarDropText($0.largestDrop))"
                } ?? text("近 48 小时", "Last 48 hours")
            )
            .font(.system(size: metrics.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (alerts.isEmpty ? Color.green : Color.orange).opacity(0.08),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    private func radarDegradationRow(
        _ alert: RadarDegradationAlert
    ) -> some View {
        HStack(spacing: 6) {
            Text(radarModelEffortLabel(alert))
                .font(.system(size: metrics.label, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("IQ \(DisplayFormatters.iqScore(alert.iq))")
                .font(.system(size: metrics.label, weight: .medium, design: .monospaced))
                .frame(width: 58, alignment: .trailing)
            Text("24h ↓\(radarDropText(alert.from24HourHighIQ))")
                .font(.system(size: metrics.caption, weight: .medium, design: .monospaced))
                .foregroundStyle(.orange)
                .frame(width: 74, alignment: .trailing)
            Text("48h ↓\(radarDropText(alert.from48HourHighIQ))")
                .font(.system(size: metrics.caption, weight: .medium, design: .monospaced))
                .foregroundStyle(.orange)
                .frame(width: 74, alignment: .trailing)
        }
    }

    private func radarRecommendationCard(
        _ group: RadarRecommendationGroup,
        index: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(radarRecommendationTitle(group, index: index))
                .font(.system(size: metrics.label, weight: .semibold))
            ForEach(
                Array(group.validItems.enumerated()),
                id: \.offset
            ) { _, item in
                HStack(spacing: 6) {
                    Text(radarModelEffortLabel(item))
                        .font(.system(size: metrics.label, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("IQ \(DisplayFormatters.iqScore(item.iq))")
                        .font(.system(size: metrics.label, weight: .medium, design: .monospaced))
                        .frame(width: 60, alignment: .trailing)
                    Text(DisplayFormatters.costUSD(item.averageCostUSD))
                        .font(.system(size: metrics.label, weight: .medium, design: .monospaced))
                        .frame(width: 64, alignment: .trailing)
                    Text(radarMinutesText(item.averageDurationMinutes))
                        .font(.system(size: metrics.label, weight: .medium, design: .monospaced))
                        .frame(width: 54, alignment: .trailing)
                }
            }
            expandableCaptionText(
                radarRecommendationExplanation(group),
                key: "radar-recommendation-\(group.key ?? "unknown")-\(index)",
                collapsedLines: 2
            )
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func preferredDailyRecommendation(
        in groups: [RadarRecommendationGroup]
    ) -> RadarRecommendationItem? {
        let daily = groups.first {
            normalizedRecommendationKey($0.key) == "daily-development"
        }
        return daily?.validItems.first
    }

    private var radarInsightsUpdatedLabel: String? {
        guard let value = state.radarInsights?.sourceUpdatedAt
                ?? state.radarInsights?.generatedAt,
              let date = RadarDateParser.date(from: value) else {
            return nil
        }
        let formatted = DisplayFormatters.compactDateTime(date)
        return text("\(formatted) 更新", "Updated \(formatted)")
    }

    private func radarInsightsCountLabel(
        groups: [RadarRecommendationGroup],
        alerts: [RadarDegradationAlert]
    ) -> String {
        text(
            "\(groups.count) 类 · \(alerts.count) 警报",
            "\(groups.count) \(groups.count == 1 ? "group" : "groups") · "
                + "\(alerts.count) \(alerts.count == 1 ? "alert" : "alerts")"
        )
    }

    private func radarRecommendationTitle(
        _ group: RadarRecommendationGroup,
        index: Int
    ) -> String {
        switch normalizedRecommendationKey(group.key) {
        case "daily-development":
            return text("日常开发", "Daily development")
        case "hard-problems":
            return text("难题攻坚", "Hard problems")
        case "background-automation":
            return text("后台自动化", "Background automation")
        case "lobster-tasks", "long-running-agents":
            return text("轻量长任务", "Lightweight long tasks")
        default:
            if language == .zhHans, let title = nonEmpty(group.title) {
                return title
            }
            return text("推荐 \(index + 1)", "Recommendation \(index + 1)")
        }
    }

    private func radarRecommendationExplanation(
        _ group: RadarRecommendationGroup
    ) -> String {
        if language == .zhHans,
           let rule = group.rule?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rule.isEmpty {
            return rule
        }
        switch normalizedRecommendationKey(group.key) {
        case "daily-development":
            return "Balances intelligence, speed, and cost for everyday work."
        case "hard-problems":
            return "Prioritizes the highest measured intelligence for difficult work."
        case "background-automation":
            return "Keeps intelligence sufficient, then favors lower cost."
        case "lobster-tasks", "long-running-agents":
            return "Prioritizes value for long-running tasks with modest intelligence needs."
        default:
            return text(
                "由 CodexRadar 根据最新分布式众测生成。",
                "Generated by CodexRadar from the latest distributed runs."
            )
        }
    }

    private func normalizedRecommendationKey(_ key: String?) -> String {
        key?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            ?? ""
    }

    private func radarModelEffortLabel(
        _ item: RadarRecommendationItem
    ) -> String {
        radarModelEffortLabel(model: item.model, effort: item.effort)
    }

    private func radarModelEffortLabel(
        _ item: RadarDegradationAlert
    ) -> String {
        radarModelEffortLabel(model: item.model, effort: item.effort)
    }

    private func radarModelEffortLabel(
        model: String?,
        effort: String?
    ) -> String {
        let normalizedModel = model?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let modelLabel: String
        switch normalizedModel {
        case "gpt-5.6-sol":
            modelLabel = "Sol"
        case "gpt-5.6-terra":
            modelLabel = "Terra"
        case "gpt-5.6-luna":
            modelLabel = "Luna"
        case "gpt-5.5":
            modelLabel = "GPT-5.5"
        default:
            modelLabel = nonEmpty(model)
                ?? text("未知模型", "Unknown model")
        }
        let effortLabel = nonEmpty(effort)?.lowercased()
        return [modelLabel, effortLabel].compactMap { $0 }.joined(separator: " ")
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func radarDropText(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else {
            return DisplayFormatters.percentPlaceholder
        }
        return String(
            format: "%.1f",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
    }

    private func radarMinutesText(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else {
            return DisplayFormatters.percentPlaceholder
        }
        return text(
            "\(Int(value.rounded()))分",
            "\(Int(value.rounded()))m"
        )
    }

    @ViewBuilder
    private var codexRadarQuotaSection: some View {
        if let quotaRadar = state.modelIQ?.quotaRadar,
           !quotaRadar.rows.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                sectionTitle(text("CodexRadar 额度雷达", "CodexRadar Quota Radar"), systemImage: "chart.bar.xaxis")
                quotaRadarTable(quotaRadar)
                expandableCaptionText(
                    quotaRadarSummary(quotaRadar),
                    key: "quota-radar-summary-\(quotaRadar.updatedAt ?? "")-\(quotaRadar.basisWindowLabel ?? "")",
                    collapsedLines: 3
                )
            }
        }
    }

    @ViewBuilder
    private var codexRadarFastSection: some View {
        if let fastRadar = state.current?.fastRadar,
           !fastRadar.summary.isEmpty || !fastRadar.rows.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    sectionTitle(text("CodexRadar Fast 雷达", "CodexRadar Fast Radar"), systemImage: "bolt.circle")
                    Spacer(minLength: 8)
                    if let updatedLabel = fastRadar.updatedLabel, !updatedLabel.isEmpty {
                        Text(updatedLabel)
                            .font(.system(size: metrics.caption, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }
                if let subtitle = fastRadar.subtitle, !subtitle.isEmpty {
                    expandableCaptionText(
                        subtitle,
                        key: "fast-radar-subtitle-\(fastRadar.updatedLabel ?? "")-\(subtitle)",
                        collapsedLines: 2
                    )
                }
                if !fastRadar.summary.isEmpty {
                    HStack(spacing: Layout.tileSpacing) {
                        ForEach(fastRadar.summary.prefix(3)) { item in
                            fastRadarSummaryTile(item)
                        }
                    }
                }
                if !fastRadar.rows.isEmpty {
                    fastRadarTable(fastRadar)
                }
                if let method = fastRadar.method, !method.isEmpty {
                    expandableCaptionText(
                        method,
                        key: "fast-radar-method-\(fastRadar.updatedLabel ?? "")",
                        collapsedLines: 3
                    )
                }
            }
        }
    }

    private var radarTitle: String {
        if codexRadarSignalRetired {
            return text(
                "重置、额度、智能洞察、Fast 与模型雷达",
                "Reset, quota, insights, Fast and model radar"
            )
        }
        return state.current?.lastWindow?.title ?? text("还没有加载 CodexRadar 状态", "No CodexRadar status loaded")
    }

    private var radarFocus: String {
        if codexRadarSignalRetired {
            return text(
                "重置 + 额度 + 推荐/预警 + Model IQ",
                "Reset + Quota + Insights + Model IQ"
            )
        }
        return state.current?.lastWindow?.windowHuman ?? text("未知", "unknown")
    }

    private var radarLegacyStatus: String {
        if codexRadarSignalRetired {
            return text("已下架", "retired")
        }
        return state.current?.lastWindow?.scope ?? text("未知", "unknown")
    }

    private var radarSummary: String {
        if codexRadarSignalRetired {
            return text(
                "CodexRadar 当前公开重置雷达、额度雷达、场景推荐、降智预警、Fast 性能对比与模型质量：reset 研判、公开额度估算、Model IQ、速度、费用、cache 命中率和社区体感分。",
                "CodexRadar currently publishes reset judgement, quota radar, scenario recommendations, degradation alerts, Fast performance comparisons, and model quality: reset calls, public quota estimates, Model IQ, speed, cost, cache hit rate, and community ratings."
            )
        }
        return state.current?.lastWindow?.summary ?? text(
            "还没有读取到 CodexRadar 公开信号。",
            "CodexRadar public signal has not been loaded yet."
        )
    }

    private var predictionSection: some View {
        let summary = state.prediction?.reasoningSummary ?? text(
            "还没有读取到预测摘要。",
            "No prediction summary loaded."
        )
        let level = state.prediction?.level ?? state.current?.prediction?.level ?? ""

        return VStack(alignment: .leading, spacing: 7) {
            sectionTitle(text("Prediction 预测", "Prediction"), systemImage: "chart.line.uptrend.xyaxis")
            HStack {
                labelPair(text("等级", "Level"), predictionLevelText(state.prediction?.level ?? state.current?.prediction?.level))
                Spacer()
                labelPair("24h", probability(state.prediction?.probability24h ?? state.current?.prediction?.probability24h))
                Spacer()
                labelPair("48h", probability(state.prediction?.probability48h ?? state.current?.prediction?.probability48h))
            }
            expandableMenuText(
                summary,
                key: "prediction-summary-\(level)-\(summary)",
                collapsedLines: 2,
                fontSize: metrics.label
            )
        }
    }

    private var iqSection: some View {
        collapsibleSection(
            isExpanded: renderedExpansionBinding(for: .modelIQ),
            systemImage: DashboardSection.modelIQ.systemImage,
            title: DashboardSection.modelIQ.label(language: language),
            trailing: DisplayFormatters.iqScore(
                state.modelIQ?.latest?.iqScore
            )
        ) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    labelPair(
                        "IQ",
                        DisplayFormatters.iqScore(
                            state.modelIQ?.latest?.iqScore
                        )
                    )
                    Spacer()
                    let passed = state.modelIQ?.latest?.passed.map(String.init) ?? "?"
                    let tasks = state.modelIQ?.latest?.tasks.map(String.init) ?? "?"
                    labelPair(modelIQResultLabel, "\(passed)/\(tasks)")
                    Spacer()
                    labelPair(
                        text("状态", "Status"),
                        state.modelIQ?.latest?.status ?? text("未知", "unknown")
                    )
                }
                if let latest = state.modelIQ?.latest {
                    HStack {
                        labelPair(
                            latest.usesPerTaskAverages
                                ? text("单题耗时", "Avg time")
                                : text("耗时", "Time"),
                            modelIQTimeText(latest)
                        )
                        Spacer()
                        labelPair(
                            latest.usesPerTaskAverages
                                ? text("单题费用", "Avg cost")
                                : text("费用", "Cost"),
                            DisplayFormatters.costUSD(
                                latest.displayedCostUSD
                            )
                        )
                        Spacer()
                        labelPair("Cache", latest.cacheHitRateText)
                        Spacer()
                        labelPair(
                            text("体感", "Rating"),
                            modelRatingText(
                                state.modelRatings?.rating(for: latest)
                            )
                        )
                    }
                }
                if let source = state.modelIQ?.dataSource,
                   let url = source.linkURL {
                    HStack {
                        Spacer()
                        Link(destination: url) {
                            HStack(spacing: 3) {
                                if let validCells = source.validCells {
                                    Text(text(
                                        "\(validCells) 条分布式结果",
                                        "\(validCells) distributed results"
                                    ))
                                } else {
                                    Text(text(
                                        "打开分布式雷达",
                                        "Open distributed radar"
                                    ))
                                }
                                Image(systemName: "arrow.up.right.square")
                            }
                            .font(.system(
                                size: metrics.caption,
                                weight: .medium
                            ))
                            .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .help(text(
                            "打开 CodexRadar 分布式雷达",
                            "Open CodexRadar distributed radar"
                        ))
                    }
                }
                if let rows = state.modelIQ?.latestRows,
                   rows.count > 1,
                   store.isDashboardDisclosureVisible(.modelIQDetails) {
                    collapsibleSection(
                        isExpanded: modelIQDetailsExpansionBinding,
                        systemImage: "square.grid.2x2",
                        title: text("全部模型 IQ", "All model IQ"),
                        trailing: text(
                            "\(rows.count) 组",
                            "\(rows.count) configs"
                        )
                    ) {
                        modelIQComparisonTable(rows)
                    }
                }
            }
        }
    }

    private func modelIQComparisonTable(_ rows: [ModelIQLatestRow]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(text("多模型", "Models"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("IQ")
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(
                        width: metrics.modelIQScoreColumnWidth,
                        alignment: .trailing
                    )
                Text(modelIQResultLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(
                        width: metrics.modelIQResultColumnWidth,
                        alignment: .trailing
                    )
                Text(text("体感", "Rating"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(
                        width: metrics.modelIQRatingColumnWidth,
                        alignment: .trailing
                    )
            }
            .font(.system(size: metrics.caption, weight: .semibold))
            .foregroundStyle(.secondary)

            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(modelIQRowLabel(row))
                            .font(.system(size: metrics.label, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(DisplayFormatters.iqScore(row.snapshot.iqScore))
                            .font(.system(size: metrics.label, weight: .medium, design: .monospaced))
                            .foregroundStyle(iqColor(for: row.snapshot))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .frame(
                                width: metrics.modelIQScoreColumnWidth,
                                alignment: .trailing
                            )
                        Text(modelIQProbeText(row.snapshot))
                            .font(.system(size: metrics.label, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .frame(
                                width: metrics.modelIQResultColumnWidth,
                                alignment: .trailing
                            )
                        Text(modelRatingCompactText(state.modelRatings?.rating(for: row.snapshot)))
                            .font(.system(size: metrics.label, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .frame(
                                width: metrics.modelIQRatingColumnWidth,
                                alignment: .trailing
                            )
                    }
                    if row.snapshot.usesPerTaskAverages {
                        Text(modelIQAverageDetailText(row.snapshot))
                            .font(.system(size: metrics.caption))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
            }
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func quotaRadarTable(_ quotaRadar: QuotaRadar) -> some View {
        let showsFiveHourValues = quotaRadar.showsFiveHourValues
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(text("档位", "Tier"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if showsFiveHourValues {
                    Text("5h")
                        .frame(width: 66, alignment: .trailing)
                }
                Text("7d")
                    .frame(width: 78, alignment: .trailing)
                Text(text("来源", "Basis"))
                    .frame(width: 62, alignment: .trailing)
            }
            .font(.system(size: metrics.caption, weight: .semibold))
            .foregroundStyle(.secondary)

            ForEach(quotaRadar.rows) { row in
                HStack(spacing: 6) {
                    Text(row.tier ?? text("未知档位", "Unknown"))
                        .font(.system(size: metrics.label, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if showsFiveHourValues {
                        Text(DisplayFormatters.costUSD(row.fiveHourUSD))
                            .font(.system(size: metrics.label, weight: .medium, design: .monospaced))
                            .frame(width: 66, alignment: .trailing)
                    }
                    Text(DisplayFormatters.costUSD(row.sevenDayUSD))
                        .font(.system(size: metrics.label, weight: .medium, design: .monospaced))
                        .frame(width: 78, alignment: .trailing)
                    Text(quotaRadarBasisText(row.basis))
                        .font(.system(size: metrics.label, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: 62, alignment: .trailing)
                }
            }
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func fastRadarSummaryTile(_ item: FastRadarSummaryItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.label ?? text("指标", "Metric"))
                .font(.system(size: metrics.caption, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
            Text(item.value ?? DisplayFormatters.percentPlaceholder)
                .font(.system(size: metrics.label, weight: .semibold, design: .monospaced))
                .foregroundStyle(fastMetricColor(item.value))
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func fastRadarTable(_ fastRadar: FastRadar) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(text("模型", "Model"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("E2E")
                    .frame(width: 72, alignment: .trailing)
                Text("TTFT")
                    .frame(width: 68, alignment: .trailing)
                Text("TPS")
                    .frame(width: 68, alignment: .trailing)
            }
            .font(.system(size: metrics.caption, weight: .semibold))
            .foregroundStyle(.secondary)

            ForEach(fastRadar.rows) { row in
                HStack(spacing: 6) {
                    Text(row.model ?? text("未知", "Unknown"))
                        .font(.system(size: metrics.label, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    fastRadarMetricValue(row.e2e)
                        .frame(width: 72, alignment: .trailing)
                    fastRadarMetricValue(row.ttft)
                        .frame(width: 68, alignment: .trailing)
                    fastRadarMetricValue(row.tps)
                        .frame(width: 68, alignment: .trailing)
                }
            }
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func fastRadarMetricValue(_ metric: FastRadarMetric?) -> some View {
        Text(metric?.value ?? DisplayFormatters.percentPlaceholder)
            .font(.system(size: metrics.label, weight: .medium, design: .monospaced))
            .foregroundStyle(fastMetricColor(metric?.value))
            .lineLimit(1)
            .minimumScaleFactor(0.58)
            .help(metricHelp(metric))
    }

    private func fastMetricColor(_ value: String?) -> Color {
        let value = value ?? ""
        if value.contains("慢") || value.lowercased().contains("slow") {
            return .red
        }
        if value.contains("快") || value.contains("⚡") || value.lowercased().contains("faster") {
            return .green
        }
        return .secondary
    }

    private func metricHelp(_ metric: FastRadarMetric?) -> String {
        [metric?.label, metric?.range, metric?.value]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
    }

    private func resetJudgementCard(_ card: ResetJudgementCard) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.label ?? text("未知路径", "Unknown path"))
                .font(.system(size: metrics.caption, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(card.level ?? text("未知", "unknown"))
                .font(.system(size: metrics.label, weight: .semibold))
                .foregroundStyle(resetJudgementLevelColor(card.level))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            expandableCaptionText(
                card.summary ?? "",
                key: "reset-judgement-card-\(card.id)",
                collapsedLines: 3
            )
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(resetJudgementCardBackground(card.level), in: RoundedRectangle(cornerRadius: 8))
    }

    private func resetJudgementLevelColor(_ level: String?) -> Color {
        let normalized = level?.lowercased() ?? ""
        if normalized.contains("高") || normalized.contains("high") {
            return .green
        }
        if normalized.contains("低") || normalized.contains("low") {
            return .orange
        }
        return .accentColor
    }

    private func resetJudgementCardBackground(_ level: String?) -> Color {
        resetJudgementLevelColor(level).opacity(0.10)
    }

    private func resetJudgementReasonsText(_ judgement: ResetJudgement) -> String {
        guard !judgement.reasons.isEmpty else {
            return text("CodexRadar 暂无原因摘要。", "No CodexRadar reason summary yet.")
        }
        return judgement.reasons.joined(separator: " ")
    }

    private func expandableCaptionText(
        _ content: String,
        key: String,
        collapsedLines: Int
    ) -> some View {
        expandableMenuText(
            content,
            key: key,
            collapsedLines: collapsedLines,
            fontSize: metrics.caption
        )
    }

    private func expandableMenuText(
        _ content: String,
        key: String,
        collapsedLines: Int,
        fontSize: CGFloat,
        weight: Font.Weight? = nil,
        color: Color = .secondary
    ) -> some View {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let contentFont = weight.map { Font.system(size: fontSize, weight: $0) } ?? Font.system(size: fontSize)

        return TruncationAwareExpandableText(
            content: trimmed,
            key: key,
            collapsedLines: collapsedLines,
            contentFont: contentFont,
            controlFont: .system(size: metrics.caption, weight: .medium),
            color: color,
            expandLabel: text("全文", "Full text"),
            collapseLabel: text("收起", "Collapse"),
            expandHelp: text("点击查看全文", "Click to show full text"),
            collapseHelp: text("点击收起", "Click to collapse"),
            expandedKeys: $expandedTextKeys
        )
    }

    private func copyCommunityPrompt(_ prompt: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(prompt, forType: .string)
        copiedCommunityPrompt = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedCommunityPrompt = false
        }
    }

    private func resetCreditSnapshotView(_ snapshot: ResetCreditSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                labelPair(text("上次查询", "Last check"), DisplayFormatters.compactDateTime(snapshot.checkedAt))
                Spacer()
            labelPair(text("可用", "Available"), "\(snapshot.effectiveAvailableCount)")
            }
            if snapshot.credits.isEmpty {
                expandableCaptionText(
                    text(
                        "没有读取到重置卡。可能当前账号没有可展示的 reset credit，或接口返回结构已变化。",
                        "No reset credits were found. This account may have none to show, or the endpoint shape changed."
                    ),
                    key: "reset-credit-empty-snapshot-\(snapshot.checkedAt.timeIntervalSince1970)",
                    collapsedLines: 3
                )
            } else {
                ForEach(Array(snapshot.credits.indices), id: \.self) { index in
                    resetCreditRow(snapshot.credits[index], index: index)
                }
            }
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func resetCreditRow(_ credit: ResetCredit, index: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(text("重置卡", "Credit")) \(index + 1) · \(resetCreditStatusText(credit))")
                    .font(.system(size: metrics.caption, weight: .semibold))
                    .foregroundStyle(resetCreditColor(credit))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(resetCreditTitle(credit))
                    .font(.system(size: metrics.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("\(text("发放", "Issued")) \(DisplayFormatters.compactDateTime(credit.grantedAt))")
                    .font(.system(size: metrics.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(text("过期", "Expires")) \(DisplayFormatters.compactDateTime(credit.expiresAt))")
                    .font(.system(size: metrics.caption, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(resetCreditRemainingText(credit))
                    .font(.system(size: metrics.caption, weight: .medium))
                    .foregroundStyle(resetCreditColor(credit))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    private func resetCreditTitle(_ credit: ResetCredit) -> String {
        guard let title = credit.title, !title.isEmpty else {
            return text("Full reset（周额度 + 5h）", "Full reset (Weekly + 5h)")
        }
        let normalized = title.lowercased()
        if normalized.contains("full reset") && normalized.contains("weekly") {
            return text("Full reset（周额度 + 5h）", "Full reset (Weekly + 5h)")
        }
        return title
    }

    private func resetCreditStatusText(_ credit: ResetCredit) -> String {
        let normalized = credit.status?.lowercased() ?? ""
        if credit.redeemedAt != nil || normalized.contains("redeem") {
            return text("已使用", "used")
        }
        if credit.isExpired() {
            return text("已过期", "expired")
        }
        if normalized == "available" {
            return text("可用", "available")
        }
        return credit.status ?? text("未知", "unknown")
    }

    private func resetCreditRemainingText(_ credit: ResetCredit) -> String {
        guard let expiresAt = credit.expiresAt else {
            return text("过期未知", "expiry unknown")
        }
        if credit.redeemedAt != nil {
            return text("已使用", "used")
        }
        if credit.isExpired() {
            return text("已过期", "expired")
        }
        let remaining = DisplayFormatters.relativeFuture(expiresAt)
        return text("剩余 \(remaining)", "\(remaining) left")
    }

    private func resetCreditColor(_ credit: ResetCredit) -> Color {
        let normalized = credit.status?.lowercased() ?? ""
        if credit.redeemedAt != nil || normalized.contains("redeem") {
            return .secondary
        }
        if credit.isExpired() {
            return .red
        }
        if let expiresAt = credit.expiresAt,
           expiresAt.timeIntervalSinceNow < 3 * 86_400 {
            return .orange
        }
        if credit.isAvailable {
            return .green
        }
        return .accentColor
    }

    private func quotaRadarBasisText(_ basis: String?) -> String {
        guard let basis, !basis.isEmpty else {
            return text("未知", "unknown")
        }
        let lowercased = basis.lowercased()
        if lowercased.contains("measured") {
            if lowercased.contains("7d") {
                return text("7d实测", "7d measured")
            }
            if lowercased.contains("5h") {
                return text("5h实测", "5h measured")
            }
            return text("实测", "measured")
        }
        if lowercased.contains("model") || lowercased.contains("/") {
            return text("推测", "estimate")
        }
        return basis
    }

    private func quotaRadarSummary(_ quotaRadar: QuotaRadar) -> String {
        let update = DisplayFormatters.compactDateTime(RadarDateParser.date(from: quotaRadar.updatedAt))
        let basis = quotaRadar.basisWindowLabel ?? text("未知窗口", "unknown window")
        let cost = DisplayFormatters.costUSD(quotaRadar.costUSD)
        let trend = quotaRadar.sevenDayTrendDelta20x.map { delta in
            quotaRadarDeltaText(delta)
        }
        if let trend {
            return text(
                "更新 \(update)；按 \(basis) 校准，20x Pro 7d 较上一轮 \(trend)。5x/Plus 为按比例推测，不是本机剩余额度。",
                "Updated \(update); calibrated from \(basis), 20x Pro 7d changed \(trend) from the prior sample. 5x/Plus are scaled estimates, not local remaining quota."
            )
        }
        return text(
            "更新 \(update)；本次校准消耗约 \(cost)。这是 CodexRadar 的公开额度等价值估算，不是本机剩余额度。",
            "Updated \(update); calibration cost about \(cost). These are CodexRadar public quota-equivalent estimates, not local remaining quota."
        )
    }

    private func quotaRadarDeltaText(_ value: Double) -> String {
        guard value.isFinite else {
            return DisplayFormatters.percentPlaceholder
        }
        let sign = value >= 0 ? "+" : "-"
        return "\(sign)\(DisplayFormatters.costUSD(abs(value)))"
    }

    private func modelIQRowLabel(_ row: ModelIQLatestRow) -> String {
        if let label = row.label, !label.isEmpty {
            return label
        }
        let parts = [row.snapshot.model, row.snapshot.reasoningEffort].compactMap { $0 }
        return parts.isEmpty ? text("未知模型", "Unknown") : parts.joined(separator: " ")
    }

    private func modelIQProbeText(_ snapshot: ModelIQSnapshot) -> String {
        let passed = snapshot.passed.map(String.init) ?? "?"
        let tasks = snapshot.tasks.map(String.init) ?? "?"
        return "\(passed)/\(tasks)"
    }

    private var isDistributedModelIQ: Bool {
        state.modelIQ?.dataSource?.isDistributedCommunityRuns == true
            || state.modelIQ?.latest?.usesPerTaskAverages == true
    }

    private var modelIQResultLabel: String {
        isDistributedModelIQ ? text("通过", "Passed") : text("探针", "Probe")
    }

    private func modelIQAverageDetailText(_ snapshot: ModelIQSnapshot) -> String {
        let cost = DisplayFormatters.costUSD(snapshot.displayedCostUSD)
        let time = modelIQTimeText(snapshot)
        let cache = snapshot.cacheHitRateText
        let cacheSuffix = cache == DisplayFormatters.percentPlaceholder ? "" : " · Cache \(cache)"
        return text("单题 \(cost) · \(time)\(cacheSuffix)", "Per task \(cost) · \(time)\(cacheSuffix)")
    }

    private func iqColor(for snapshot: ModelIQSnapshot) -> Color {
        guard let score = snapshot.iqScore else {
            return .secondary
        }
        if score < 60 {
            return .red
        }
        if snapshot.status?.lowercased() == "red" || score < 90 {
            return .orange
        }
        return .green
    }

    private func modelRatingText(_ rating: ModelRating?) -> String {
        guard let rating,
              let average = rating.average,
              average.isFinite else {
            return DisplayFormatters.percentPlaceholder
        }
        let score = String(format: "%.1f/10", locale: Locale(identifier: "en_US_POSIX"), average)
        guard let count = rating.count, count > 0 else {
            return score
        }
        return text("\(score) · \(count)票", "\(score) · \(count) votes")
    }

    private func modelRatingCompactText(_ rating: ModelRating?) -> String {
        guard let rating,
              let average = rating.average,
              average.isFinite else {
            return DisplayFormatters.percentPlaceholder
        }
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), average)
    }

    private func modelIQTimeText(_ snapshot: ModelIQSnapshot) -> String {
        if let averageTaskSeconds = snapshot.averageTaskSeconds {
            switch language {
            case .zhHans:
                return snapshot.averageTaskTimeHuman
                    ?? "\(max(1, Int(round(averageTaskSeconds / 60))))分钟"
            case .en:
                return DisplayFormatters.minutesFromSeconds(Int(round(averageTaskSeconds)))
            }
        }
        switch language {
        case .zhHans:
            return snapshot.wallTimeHuman ?? DisplayFormatters.minutesFromSeconds(snapshot.wallSeconds)
        case .en:
            return DisplayFormatters.minutesFromSeconds(snapshot.wallSeconds)
        }
    }

    private func errorSection(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle(text("连接", "Connection"), systemImage: "exclamationmark.triangle")
            expandableMenuText(
                error,
                key: "connection-error-\(error)",
                collapsedLines: 4,
                fontSize: metrics.label
            )
        }
    }

    private var settingsSection: some View {
        collapsibleSection(
            isExpanded: renderedExpansionBinding(for: .displayAndAlerts),
            systemImage: "slider.horizontal.3",
            title: text("显示与提醒", "Display & alerts"),
            trailing: language.label
        ) {
            VStack(alignment: .leading, spacing: 10) {
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
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: Layout.tileSpacing),
                            count: hasLocalShortQuota ? 3 : 2
                        ),
                        alignment: .leading,
                        spacing: 7
                    ) {
                        metricToggle(.weeklyQuota)
                        if hasLocalShortQuota {
                            metricToggle(.shortQuota)
                        }
                        metricToggle(.quotaPace)
                        metricToggle(.codexIQ)
                        metricToggle(.signal)
                    }
                    if !hasLocalShortQuota {
                        Text(text(
                            "Codex 当前未返回 5h 短窗，已自动隐藏；恢复后选项会自动出现。",
                            "Codex is not currently returning a 5h window, so it is hidden automatically and will reappear when available."
                        ))
                        .font(.system(size: metrics.caption))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    quotaPacingOptions
                    Toggle(
                        text("状态栏 IQ 小数", "Decimal IQ in menu bar"),
                        isOn: $store.statusBarPreciseIQEnabled
                    )
                    .toggleStyle(.checkbox)
                    statusBarAdvancedOptions
                }
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: Layout.tileSpacing),
                        GridItem(.flexible(), spacing: Layout.tileSpacing),
                    ],
                    alignment: .leading,
                    spacing: 7
                ) {
                    if showsPredictionSection {
                        Toggle(text("Prediction 提醒", "Prediction alerts"), isOn: $store.predictionNotificationsEnabled)
                    }
                    Toggle(text("IQ 提醒", "IQ alerts"), isOn: $store.iqNotificationsEnabled)
                    Toggle(text("通知声音", "Notification sound"), isOn: $store.notificationSoundEnabled)
                    Toggle(text("登录时启动", "Launch at login"), isOn: $store.launchAtLoginEnabled)
                }
            }
            .toggleStyle(.checkbox)
            .font(.system(size: metrics.label))
        }
    }

    private var quotaPacingOptions: some View {
        collapsibleSection(
            isExpanded: $store.quotaPacingOptionsExpanded,
            systemImage: "clock.arrow.circlepath",
            title: text("应剩计算策略", "Pace rule"),
            trailing: quotaPacingStrategyLabel(store.quotaPacingStrategy)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text(text("点击下面任一策略即可切换。", "Click any rule below to switch."))
                    .font(.system(size: metrics.caption))
                    .foregroundStyle(.secondary)
                ForEach(QuotaPacingStrategy.allCases) { strategy in
                    quotaPacingStrategyButton(strategy)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(
                        text("使用中国节假日/调休", "Use China holidays"),
                        isOn: $store.chinaHolidayCalendarEnabled
                    )
                    .toggleStyle(.checkbox)
                    expandableCaptionText(
                        text(
                            "默认开启，仅影响“工作日”策略。已内置 2026 年法定假日和调休补班：假日按周末权重，补班按工作日权重。",
                            "On by default and only affects Workdays. Includes 2026 mainland China public holidays and makeup workdays: holidays use weekend weight; makeup days use weekday weight."
                        ),
                        key: "quota-pacing-china-holiday-description",
                        collapsedLines: 3
                    )
                }
                expandableCaptionText(
                    text(
                        "这个策略会同时影响下拉菜单里的“建议剩余”和可选状态栏段“应剩”。",
                        "This rule affects both the Target left value in the dropdown and the optional Pace menu-bar segment."
                    ),
                    key: "quota-pacing-effect-description",
                    collapsedLines: 2
                )
            }
        }
    }

    private var statusBarAdvancedOptions: some View {
        collapsibleSection(
            isExpanded: $store.statusBarAdvancedOptionsExpanded,
            systemImage: "wrench.adjustable",
            title: text("状态栏高级", "Menu bar advanced")
        ) {
            VStack(alignment: .leading, spacing: 8) {
                settingRow(title: text("分隔符", "Separator")) {
                    Picker(text("分隔符", "Separator"), selection: $store.statusBarSeparator) {
                        ForEach(StatusBarSeparator.allCases) { separator in
                            Text(separator.label(language: language)).tag(separator)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                settingRow(title: text("左右留白", "Side padding")) {
                    Picker(text("左右留白", "Side padding"), selection: $store.statusBarHorizontalPadding) {
                        ForEach(StatusBarHorizontalPadding.allCases) { padding in
                            Text(padding.label(language: language)).tag(padding)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                settingRow(title: text("字体", "Font")) {
                    Picker(text("字体", "Font"), selection: $store.statusBarFontScale) {
                        ForEach(StatusBarFontScale.allCases) { scale in
                            Text(scale.label(language: language)).tag(scale)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                settingRow(title: text("IQ 显示", "IQ display")) {
                    Picker(text("IQ 显示", "IQ display"), selection: $store.statusBarIQDisplayMode) {
                        ForEach(StatusBarIQDisplayMode.allCases) { mode in
                            Text(iqDisplayModeLabel(mode)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Toggle(
                    text("状态栏显示 %", "Show % in menu bar"),
                    isOn: percentSymbolBinding
                )
                .toggleStyle(.checkbox)
                HStack(alignment: .center, spacing: Layout.tileSpacing) {
                    labelPair(text("预览", "Preview"), menuBarTitle)
                    Spacer()
                    Button(text("恢复默认", "Reset")) {
                        store.resetStatusBarAdvancedOptions()
                    }
                    .font(.system(size: metrics.caption, weight: .medium))
                }
                expandableCaptionText(
                    text(
                        "高级选项只影响菜单栏标题；下拉菜单里的精确数值保持完整。",
                        "Advanced options only change the menu bar title; dropdown values stay complete."
                    ),
                    key: "status-bar-advanced-description",
                    collapsedLines: 2
                )
            }
        }
    }

    private var updateSection: some View {
        collapsibleSection(
            isExpanded: renderedExpansionBinding(for: .updates),
            systemImage: DashboardSection.updates.systemImage,
            title: DashboardSection.updates.label(language: language),
            trailing: updateSectionSummary,
            isExpansionLocked: updateRequiresAttention
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: Layout.tileSpacing) {
                    Toggle(
                        text("自动更新", "Auto update"),
                        isOn: $store.automaticUpdatesEnabled
                    )
                    .toggleStyle(.checkbox)
                    .font(.system(size: metrics.label))
                    Spacer()
                    Text("v\(AppConstants.appVersion)")
                        .font(.system(
                            size: metrics.caption,
                            weight: .medium,
                            design: .monospaced
                        ))
                        .foregroundStyle(.secondary)
                }
                expandableMenuText(
                    updateStatusText,
                    key: "update-status-\(updateStatusText)",
                    collapsedLines: 2,
                    fontSize: metrics.caption,
                    color: updateStatusColor
                )
                HStack(spacing: Layout.tileSpacing) {
                    compactActionButton(
                        title: text("检查更新", "Check"),
                        systemImage: "arrow.clockwise"
                    ) {
                        store.checkForUpdatesNow()
                    }
                    compactActionButton(
                        title: "Changelog",
                        systemImage: "doc.text"
                    ) {
                        store.openLatestReleaseNotes()
                    }
                    compactActionButton(
                        title: "Prompts",
                        systemImage: "text.quote",
                        help: text("打开 PROMPTS.md", "Open PROMPTS.md")
                    ) {
                        store.openPromptLog()
                    }
                    compactActionButton(
                        title: "GitHub",
                        systemImage: "star",
                        help: text("打开 GitHub 仓库", "Open the GitHub repo")
                    ) {
                        store.openGitHubRepository()
                    }
                }
            }
        }
    }

    private var updateRequiresAttention: Bool {
        if case .failed = store.updatePhase {
            return true
        }
        return false
    }

    private var updateSectionSummary: String {
        switch store.updatePhase {
        case .checking:
            return text("检查中", "Checking")
        case .available(let version):
            return text("\(version) 可用", "\(version) available")
        case .downloading(let version):
            return text("下载 \(version)", "Downloading \(version)")
        case .installing(let version):
            return text("安装 \(version)", "Installing \(version)")
        case .failed:
            return text("需要处理", "Needs attention")
        case .idle, .upToDate:
            return "v\(AppConstants.appVersion)"
        }
    }

    private var previewSection: some View {
        collapsibleSection(
            isExpanded: renderedExpansionBinding(for: .preview),
            systemImage: "eye",
            title: text("调试预览", "Preview"),
            trailing: store.debugPreview.label(language: language)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Picker(text("预览", "Preview"), selection: $store.debugPreview) {
                    ForEach(DashboardPreview.allCases) { preview in
                        Text(preview.label(language: language)).tag(preview)
                    }
                }
                .pickerStyle(.segmented)
                .font(.system(size: metrics.label))
                expandableCaptionText(
                    text(
                        "只预览 UI；真实通知和去重仍使用 live 数据。",
                        "UI preview only; notifications still use live data."
                    ),
                    key: "debug-preview-description",
                    collapsedLines: 2
                )
            }
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
            toolbarButton(title: "GitHub", systemImage: "star") {
                store.openGitHubRepository()
            }
            toolbarButton(
                title: customizesLayout
                    ? text("完成", "Done")
                    : text("布局", "Layout"),
                systemImage: customizesLayout
                    ? "checkmark"
                    : "rectangle.3.group"
            ) {
                withAnimation(.easeInOut(duration: 0.12)) {
                    setLayoutEditorVisible(!customizesLayout)
                }
            }
            toolbarButton(title: text("退出", "Quit"), systemImage: "power") {
                store.quit()
            }
        }
    }

    private func setLayoutEditorVisible(_ isVisible: Bool) {
        cancelDashboardSectionDrag()
        if isVisible {
            store.dismissLayoutDiscoveryTip()
        }
        customizesLayout = isVisible
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

    private func collapsibleSection<Content: View>(
        isExpanded: Binding<Bool>,
        systemImage: String,
        title: String,
        trailing: String? = nil,
        isExpansionLocked: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                guard !isExpansionLocked else {
                    return
                }
                withAnimation(.easeInOut(duration: 0.12)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpansionLocked
                        ? "lock.fill"
                        : "chevron.right")
                        .font(.system(size: metrics.caption, weight: .semibold))
                        .rotationEffect(.degrees(
                            !isExpansionLocked && isExpanded.wrappedValue
                                ? 90
                                : 0
                        ))
                        .foregroundStyle(.secondary)
                    Image(systemName: systemImage)
                    Text(title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Spacer(minLength: 6)
                    if let trailing {
                        Text(trailing)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                }
                .font(.system(size: metrics.caption, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(
                isExpansionLocked
                    ? text(
                        "需要处理，暂时保持展开",
                        "Needs attention; temporarily remains expanded"
                    )
                    : title
            )
            .accessibilityLabel(title)
            .accessibilityValue(
                isExpansionLocked
                    ? text(
                        "需要处理，暂时保持展开",
                        "Needs attention; temporarily expanded"
                    )
                    : (
                        isExpanded.wrappedValue
                            ? text("已展开", "Expanded")
                            : text("已折叠", "Collapsed")
                    )
            )
            .accessibilityHint(
                isExpansionLocked
                    ? text(
                        "处理完成后可再次收起",
                        "Can be collapsed after the issue is resolved"
                    )
                    : text(
                        "点击展开或收起",
                        "Click to expand or collapse"
                    )
            )

            if isExpanded.wrappedValue {
                content()
                    .padding(.top, 6)
            }
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
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(metric.value(
                for: state,
                language: language,
                pacingStrategy: store.quotaPacingStrategy,
                holidayCalendar: store.quotaPacingHolidayCalendar
            ))
                .font(.system(size: metrics.badge, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(.horizontal, 7)
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

    private func pacingTile(title: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: metrics.caption))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(value)
                .font(.system(size: metrics.badge, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(detail)
                .font(.system(size: metrics.caption))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func quotaPacingStrategyCard(_ strategy: QuotaPacingStrategy) -> some View {
        let selected = store.quotaPacingStrategy == strategy
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(quotaPacingStrategyLabel(strategy))
                    .font(.system(size: metrics.caption, weight: .semibold))
                if selected {
                    Text(text("当前", "Current"))
                        .font(.system(size: metrics.caption, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor, in: Capsule())
                }
            }
            Text(quotaPacingStrategySummary(strategy))
                .font(.system(size: metrics.caption))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(quotaPacingStrategyBestFor(strategy))
                .font(.system(size: metrics.caption, weight: .medium))
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Color.accentColor.opacity(0.12) : Color(nsColor: .quaternaryLabelColor).opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
    }

    private func quotaPacingStrategyButton(_ strategy: QuotaPacingStrategy) -> some View {
        Button {
            store.quotaPacingStrategy = strategy
        } label: {
            quotaPacingStrategyCard(strategy)
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(quotaPacingStrategyLabel(strategy))
        .accessibilityHint(text("切换应剩计算策略", "Switch pace rule"))
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
                .minimumScaleFactor(0.8)
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
        case "medium_high", "medium-high":
            return text("中高", "medium-high")
        case "medium":
            return text("中", "medium")
        case "medium_low", "medium-low":
            return text("中低", "medium-low")
        case "low":
            return text("低", "low")
        default:
            return text("未知", "unknown")
        }
    }

    private var percentSymbolBinding: Binding<Bool> {
        Binding(
            get: { store.statusBarPercentDisplayMode == .symbol },
            set: { store.statusBarPercentDisplayMode = $0 ? .symbol : .numberOnly }
        )
    }

    private func iqDisplayModeLabel(_ mode: StatusBarIQDisplayMode) -> String {
        switch mode {
        case .raw:
            return text("原值", "Raw")
        case .dividedBy10Integer:
            return text("/10 整数", "/10 int")
        case .dividedBy10Decimal:
            return text("/10 小数", "/10 dec")
        }
    }

    private func quotaPacingStrategyLabel(_ strategy: QuotaPacingStrategy) -> String {
        switch strategy {
        case .timeProportional:
            return text("按时间", "Time")
        case .sevenDay:
            return text("每日", "Daily")
        case .reserveTwenty:
            return text("留余", "Reserve")
        case .workdayWeighted:
            return text("工作日", "Workdays")
        case .frontLoaded:
            return text("先用", "Front-load")
        }
    }

    private func quotaPacingStrategySummary(_ strategy: QuotaPacingStrategy) -> String {
        switch strategy {
        case .timeProportional:
            return text(
                "连续按 reset 窗口时间比例计算：窗口过了 20%，建议剩余就是 80%。数据每 60 秒刷新；状态栏显示整数，所以周窗口大约 1 小时 41 分钟变化 1%。",
                "Continuous reset-window timing: if 20% of the window elapsed, target remaining is 80%. Data refreshes every 60s; integer menu-bar display moves about every 1h 41m for a weekly window."
            )
        case .sevenDay:
            return text(
                "按天级台阶计算：把周额度分成 7 份，进入第 N 天后显示当天结束前建议剩余。它不会按小时慢慢变，而是每天推进一格。",
                "Daily steps: split weekly quota into seven chunks. On day N, it shows the remaining target for the end of that day. It does not drift hour by hour; it steps once per day."
            )
        case .reserveTwenty:
            return text(
                "前 6 天只规划使用 80%，始终给突发任务留 20% 缓冲；最后 1 天再把这 20% 慢慢释放出来。",
                "Plans only 80% for roughly the first six days, keeping a 20% buffer for surprises; the final day gradually releases that buffer."
            )
        case .workdayWeighted:
            return text(
                "按本机日历的天级预算计算：工作日权重 1，周末权重 0.35；进入当天后会把当天预算计入建议用量，reset 当天按截止时刻折算。",
                "Uses local calendar day buckets: weekdays weigh 1 and weekends 0.35. The current day counts once entered, and the reset day is prorated to the reset time."
            )
        case .frontLoaded:
            return text(
                "前半个窗口建议用掉约 70%，后半个窗口再用剩下 30%。它会更早提醒你别把额度留到 reset 前才用。",
                "Targets about 70% usage by the halfway point, then spends the remaining 30% later. It nudges you not to leave quota unused until right before reset."
            )
        }
    }

    private func quotaPacingStrategyBestFor(_ strategy: QuotaPacingStrategy) -> String {
        switch strategy {
        case .timeProportional:
            return text(
                "适合：想让 7 天额度平滑、均匀地用完。",
                "Best for: spending the weekly quota smoothly across the full reset window."
            )
        case .sevenDay:
            return text(
                "适合：按每天固定预算安排使用，不想被小时级变化打扰。",
                "Best for: planning by daily budget without hour-level movement."
            )
        case .reserveTwenty:
            return text(
                "适合：经常遇到临时大任务，宁愿保守一点也不想太早接近限额。",
                "Best for: users who often get urgent large tasks and prefer not to approach limits too early."
            )
        case .workdayWeighted:
            return text(
                "适合：主要在工作日高强度使用，周末只是偶尔轻量使用。",
                "Best for: heavy weekday use with lighter weekend use."
            )
        case .frontLoaded:
            return text(
                "适合：reset 后就有大任务，或者不想最后发现额度还剩很多。",
                "Best for: large tasks soon after reset, or avoiding unused quota near the end."
            )
        }
    }

    private func quotaPacingDeltaValue(_ pacing: QuotaPacingSnapshot) -> String {
        "\(abs(pacing.roundedRemainingDeltaPercent))%"
    }

    private func quotaPacingDeltaTitle(_ pacing: QuotaPacingSnapshot) -> String {
        let delta = pacing.roundedRemainingDeltaPercent
        if delta >= 3 {
            return text("可多用", "Can spend more")
        }
        if delta <= -3 {
            return text("超用", "Over target")
        }
        return text("接近节奏", "On pace")
    }

    private func quotaPacingDeltaDetail(_ pacing: QuotaPacingSnapshot) -> String {
        let delta = pacing.roundedRemainingDeltaPercent
        if delta >= 3 {
            return text("剩余额度高于建议", "remaining above target")
        }
        if delta <= -3 {
            return text("用量超出建议", "usage above target")
        }
        if delta > 0 {
            return text("剩余额度略高于建议", "remaining slightly above target")
        }
        if delta < 0 {
            return text("用量略超出建议", "usage slightly above target")
        }
        return text("与建议一致", "matches target")
    }

    private func quotaPacingExplanation(_ pacing: QuotaPacingSnapshot) -> String {
        let prefix = text(
            "窗口已过 \(pacing.roundedElapsedWindowPercent)%",
            "\(pacing.roundedElapsedWindowPercent)% of the window has elapsed"
        )
        let target = DisplayFormatters.percent(pacing.roundedTargetRemainingPercent)
        let actual = DisplayFormatters.percent(pacing.roundedCurrentRemainingPercent)
        let delta = abs(pacing.roundedRemainingDeltaPercent)
        let action: String
        if pacing.roundedRemainingDeltaPercent >= 3 {
            action = text("实际还剩 \(actual)，比建议多 \(delta)%，可以多用一点。", "Actual is \(actual), \(delta)% above target, so you can spend more.")
        } else if pacing.roundedRemainingDeltaPercent <= -3 {
            action = text(
                "实际还剩 \(actual)，比建议少 \(delta)%；也就是用量已超出建议 \(delta)%，建议放慢一点。",
                "Actual remaining is \(actual), \(delta)% below target; usage is \(delta)% above the suggested pace, so slow down a little."
            )
        } else if pacing.roundedRemainingDeltaPercent > 0 {
            action = text(
                "实际还剩 \(actual)，比建议多 \(delta)%，整体接近节奏。",
                "Actual remaining is \(actual), \(delta)% above target, so usage is close to pace."
            )
        } else if pacing.roundedRemainingDeltaPercent < 0 {
            action = text(
                "实际还剩 \(actual)，比建议少 \(delta)%；用量略超出建议，但整体接近节奏。",
                "Actual remaining is \(actual), \(delta)% below target; usage is slightly above the suggested pace but remains close to pace."
            )
        } else {
            action = text("实际还剩 \(actual)，与建议一致。", "Actual remaining is \(actual), exactly on target.")
        }
        switch pacing.strategy {
        case .timeProportional:
            return text(
                "\(prefix)：按 reset 窗口时间比例，建议现在应剩 \(target)。\(action)",
                "\(prefix): target remaining is \(target) by reset-window time. \(action)"
            )
        case .sevenDay:
            return text(
                "\(prefix)：按每日预算，建议现在应剩 \(target)。\(action)",
                "\(prefix): target remaining is \(target) by the daily rule. \(action)"
            )
        case .reserveTwenty:
            return text(
                "\(prefix)：按留余策略，建议现在应剩 \(target)。\(action)",
                "\(prefix): target remaining is \(target) by the reserve rule. \(action)"
            )
        case .workdayWeighted:
            return text(
                "\(prefix)：按工作日权重，建议现在应剩 \(target)。\(action)",
                "\(prefix): target remaining is \(target) by the workday-weighted rule. \(action)"
            )
        case .frontLoaded:
            return text(
                "\(prefix)：按先用策略，建议现在应剩 \(target)。\(action)",
                "\(prefix): target remaining is \(target) by the front-loaded rule. \(action)"
            )
        }
    }

    private func text(_ zhHans: String, _ en: String) -> String {
        language.text(zhHans, en)
    }

    private var actionText: String {
        if state.activeSpeedWindow {
            return text("速蹬窗口开启", "Speed window open")
        }
        if state.activeEntitlementEvent {
            return text("官方权益事件", "Official entitlement")
        }
        if state.rateLimits?.isBlocked == true {
            return text("本机限额中", "Local limit reached")
        }
        if codexRadarSignalRetired {
            return text(
                "重置、额度、智能洞察与模型雷达",
                "Reset, quota, insights and model radar"
            )
        }
        if state.recentResetClosed {
            return text(
                "上次 reset 时间是 \(DisplayFormatters.compactDateTime(lastResetAt))",
                "Last reset was \(DisplayFormatters.compactDateTime(lastResetAt))"
            )
        }
        return text("等待", "Waiting")
    }

    private var headerDetailText: String {
        if state.activeSpeedWindow {
            return text(
                "建议尽快使用 · 周额度 \(DisplayFormatters.percent(state.rateLimits?.weeklyRemainingPercent))",
                "Use soon · weekly \(DisplayFormatters.percent(state.rateLimits?.weeklyRemainingPercent))"
            )
        }
        if state.activeEntitlementEvent {
            return state.current?.lastWindow?.title ?? text("CodexRadar 记录到官方权益事件", "CodexRadar recorded an official entitlement event")
        }
        if state.rateLimits?.isBlocked == true {
            return text("本机 Codex 返回限额状态", "Local Codex reports a limit")
        }
        if codexRadarSignalRetired {
            return text(
                "CodexRadar 当前公开重置雷达 + 额度雷达 + 智能洞察 + Model IQ",
                "CodexRadar publishes reset radar + quota radar + insights + Model IQ"
            )
        }
        if state.recentResetClosed {
            if visibilityResolution(for: .quota).isVisible {
                return text(
                    "本机额度见下方 · 来源 CodexRadar",
                    "Local quota below · source CodexRadar"
                )
            }
            return text("来源 CodexRadar", "Source CodexRadar")
        }
        return text(
            "数据获取 \(DisplayFormatters.compactDateTime(state.lastUpdatedAt))",
            "Fetched \(DisplayFormatters.compactDateTime(state.lastUpdatedAt))"
        )
    }

    private var lastResetAt: Date? {
        state.current?.lastWindow?.closedDate
            ?? state.current?.checkedDate
            ?? state.lastUpdatedAt
    }

    private var codexRadarSignalRetired: Bool {
        state.current?.status?.lowercased() == "retired"
            || state.current?.lastWindow?.status?.lowercased() == "retired"
    }

    private var showsPredictionSection: Bool {
        guard !codexRadarSignalRetired else {
            return false
        }
        guard let prediction = state.prediction ?? state.current?.predictionDetail else {
            return false
        }
        if state.activeSpeedWindow || prediction.shouldNotify == true {
            return true
        }
        return prediction.level?.lowercased() != "low"
    }

    private var signalLabel: String {
        StatusMetric.signal.value(for: state, language: language)
    }

    private var headerSymbol: String {
        if state.activeSpeedWindow {
            return "bolt.circle.fill"
        }
        if state.activeEntitlementEvent {
            return "gift.circle.fill"
        }
        if state.rateLimits?.isBlocked == true {
            return "lock.circle.fill"
        }
        return "gauge.with.dots.needle.67percent"
    }

    private var headerColor: Color {
        if state.activeSpeedWindow {
            return .red
        }
        if state.activeEntitlementEvent {
            return .teal
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

    private var shortQuotaColor: Color {
        guard let remaining = state.rateLimits?.shortRemainingPercent else {
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

    private var quotaPaceColor: Color {
        guard let pacing = state.rateLimits?.quotaPacing(
            strategy: store.quotaPacingStrategy,
            holidayCalendar: store.quotaPacingHolidayCalendar
        ) else {
            return .secondary
        }
        switch pacing.status {
        case .underTarget:
            return .green
        case .onPace:
            return .teal
        case .overTarget:
            return .orange
        }
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
        case "正常", "ok":
            return .green
        case "权益", "event":
            return .teal
        case "低", "low":
            return iqColor
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

private struct DashboardSectionDropDelegate: DropDelegate {
    let targetSection: DashboardSection
    @Binding var draggedSection: DashboardSection?
    let sections: [DashboardSection]
    let move: (DashboardSection, Int) -> Void
    let commit: () -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggedSection != nil
            && info.hasItemsConforming(
                to: [.codexRadarDashboardSection]
            )
    }

    func dropEntered(info: DropInfo) {
        guard let draggedSection,
              draggedSection != targetSection,
              let targetIndex = sections.firstIndex(of: targetSection) else {
            return
        }
        move(draggedSection, targetIndex)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info: info) else {
            return false
        }
        commit()
        draggedSection = nil
        return true
    }
}

private struct TruncationAwareExpandableText: View {
    let content: String
    let key: String
    let collapsedLines: Int
    let contentFont: Font
    let controlFont: Font
    let color: Color
    let expandLabel: String
    let collapseLabel: String
    let expandHelp: String
    let collapseHelp: String
    @Binding var expandedKeys: Set<String>
    @State private var collapsedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    private var isExpanded: Bool {
        expandedKeys.contains(key)
    }

    private var canExpand: Bool {
        collapsedHeight > 0 && fullHeight > collapsedHeight + 1
    }

    var body: some View {
        Group {
            if canExpand {
                Button {
                    toggleExpandedText()
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        visibleText
                            .lineLimit(isExpanded ? nil : collapsedLines)
                        HStack(spacing: 4) {
                            Spacer(minLength: 0)
                            Text(isExpanded ? collapseLabel : expandLabel)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        }
                        .font(controlFont)
                        .foregroundStyle(Color.accentColor)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? collapseHelp : expandHelp)
            } else {
                visibleText
                    .lineLimit(collapsedLines)
            }
        }
        .background(measurementViews)
    }

    private var visibleText: some View {
        Text(content)
            .font(contentFont)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var measurementViews: some View {
        VStack(spacing: 0) {
            Text(content)
                .font(contentFont)
                .lineLimit(collapsedLines)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: CollapsedTextHeightPreferenceKey.self,
                            value: proxy.size.height
                        )
                    }
                }
                .onPreferenceChange(CollapsedTextHeightPreferenceKey.self) { height in
                    if abs(collapsedHeight - height) > 0.5 {
                        collapsedHeight = height
                    }
                }
            Text(content)
                .font(contentFont)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: FullTextHeightPreferenceKey.self,
                            value: proxy.size.height
                        )
                    }
                }
                .onPreferenceChange(FullTextHeightPreferenceKey.self) { height in
                    if abs(fullHeight - height) > 0.5 {
                        fullHeight = height
                    }
                }
        }
        .hidden()
        .accessibilityHidden(true)
    }

    private func toggleExpandedText() {
        withAnimation(.easeInOut(duration: 0.14)) {
            if expandedKeys.contains(key) {
                expandedKeys.remove(key)
            } else {
                expandedKeys.insert(key)
            }
        }
    }
}

private struct CollapsedTextHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct FullTextHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
