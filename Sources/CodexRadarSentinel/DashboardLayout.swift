import Foundation

enum DashboardSection: String, CaseIterable, Identifiable {
    case quota
    case modelIQ
    case resetCredits
    case usagePace
    case insights
    case radarDetails
    case menuBarGuide
    case displayAndAlerts
    case updates
    case preview

    var id: String {
        rawValue
    }

    var systemImage: String {
        switch self {
        case .quota:
            return "speedometer"
        case .modelIQ:
            return "brain.head.profile"
        case .resetCredits:
            return "creditcard"
        case .usagePace:
            return "chart.xyaxis.line"
        case .insights:
            return "sparkles"
        case .radarDetails:
            return "dot.radiowaves.left.and.right"
        case .menuBarGuide:
            return "menubar.rectangle"
        case .displayAndAlerts:
            return "slider.horizontal.3"
        case .updates:
            return "arrow.down.app"
        case .preview:
            return "eye"
        }
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .quota:
            return language.text("Codex 额度", "Codex Quota")
        case .modelIQ:
            return "Codex IQ"
        case .resetCredits:
            return language.text("重置卡与自动使用", "Reset credits & auto-use")
        case .usagePace:
            return language.text("用量节奏", "Usage Pace")
        case .insights:
            return language.text("CodexRadar 智能洞察", "CodexRadar Insights")
        case .radarDetails:
            return language.text("更多 CodexRadar 信息", "More from CodexRadar")
        case .menuBarGuide:
            return language.text("状态栏说明", "Menu bar guide")
        case .displayAndAlerts:
            return language.text("显示与提醒", "Display & alerts")
        case .updates:
            return language.text("版本更新", "Updates")
        case .preview:
            return language.text("调试预览", "Preview")
        }
    }

    func layoutEditorLabel(language: AppLanguage) -> String {
        if self == .resetCredits, language == .en {
            return "Reset credits"
        }
        return label(language: language)
    }
}

enum DashboardDisclosure: String, CaseIterable, Identifiable {
    case quotaHistory
    case modelIQDetails
    case radarInsightsDetails

    var id: String {
        rawValue
    }

    var parentSection: DashboardSection {
        switch self {
        case .quotaHistory:
            return .quota
        case .modelIQDetails:
            return .modelIQ
        case .radarInsightsDetails:
            return .insights
        }
    }

    var systemImage: String {
        switch self {
        case .quotaHistory:
            return "chart.line.uptrend.xyaxis"
        case .modelIQDetails:
            return "square.grid.2x2"
        case .radarInsightsDetails:
            return "list.bullet.rectangle"
        }
    }

    var isExpandedByDefault: Bool {
        false
    }

    func label(language: AppLanguage) -> String {
        switch self {
        case .quotaHistory:
            return language.text("额度历史", "Quota history")
        case .modelIQDetails:
            return language.text("全部模型 IQ", "All model IQ")
        case .radarInsightsDetails:
            return language.text(
                "场景推荐与降智预警",
                "Recommendations & alerts"
            )
        }
    }

    static func children(
        of section: DashboardSection
    ) -> [DashboardDisclosure] {
        allCases.filter { $0.parentSection == section }
    }
}

struct DashboardLayout: Equatable {
    static let orderDefaultsKey = "dashboardSectionOrderV1"
    static let expandedDefaultsKey = "dashboardSectionExpansionV1"
    static let visibilityDefaultsKey = "dashboardSectionVisibilityV1"
    static let disclosureVisibilityDefaultsKey =
        "dashboardDisclosureVisibilityV1"

    static let defaultOrder: [DashboardSection] = [
        .quota,
        .modelIQ,
        .resetCredits,
        .usagePace,
        .insights,
        .radarDetails,
        .menuBarGuide,
        .displayAndAlerts,
        .updates,
        .preview,
    ]

    static let defaultExpandedSections: Set<DashboardSection> = [
        .quota,
        .modelIQ,
        .usagePace,
        .insights,
    ]

    static let `default` = DashboardLayout(
        order: defaultOrder,
        expandedSections: defaultExpandedSections
    )

    private(set) var order: [DashboardSection]
    private(set) var expandedSections: Set<DashboardSection>
    private(set) var hiddenSections: Set<DashboardSection>
    private(set) var hiddenDisclosures: Set<DashboardDisclosure>

    init(
        order: [DashboardSection],
        expandedSections: Set<DashboardSection>,
        hiddenSections: Set<DashboardSection> = [],
        hiddenDisclosures: Set<DashboardDisclosure> = []
    ) {
        self.order = Self.normalizedOrder(order)
        self.expandedSections = expandedSections.intersection(
            Set(DashboardSection.allCases)
        )
        self.hiddenSections = hiddenSections.intersection(
            Set(DashboardSection.allCases)
        )
        self.hiddenDisclosures = hiddenDisclosures.intersection(
            Set(DashboardDisclosure.allCases)
        )
    }

    static func load(from defaults: UserDefaults) -> DashboardLayout {
        let order: [DashboardSection]
        if defaults.object(forKey: orderDefaultsKey) == nil {
            order = defaultOrder
        } else if let rawOrder = defaults.stringArray(forKey: orderDefaultsKey) {
            order = normalizedOrder(
                rawOrder.compactMap(DashboardSection.init(rawValue:))
            )
        } else {
            order = defaultOrder
        }

        let expandedSections: Set<DashboardSection>
        if defaults.object(forKey: expandedDefaultsKey) == nil {
            expandedSections = defaultExpandedSections
        } else if let rawExpanded = defaults.dictionary(
            forKey: expandedDefaultsKey
        ) {
            expandedSections = Set(
                DashboardSection.allCases.filter { section in
                    if let stored = rawExpanded[section.rawValue] as? Bool {
                        return stored
                    }
                    return defaultExpandedSections.contains(section)
                }
            )
        } else if let legacyExpanded = defaults.stringArray(
            forKey: expandedDefaultsKey
        ) {
            expandedSections = Set(
                legacyExpanded.compactMap(
                    DashboardSection.init(rawValue:)
                )
            )
        } else {
            expandedSections = defaultExpandedSections
        }

        let hiddenSections: Set<DashboardSection>
        if let rawVisibility = defaults.dictionary(
            forKey: visibilityDefaultsKey
        ) {
            hiddenSections = Set(
                DashboardSection.allCases.filter { section in
                    (rawVisibility[section.rawValue] as? Bool) == false
                }
            )
        } else {
            hiddenSections = []
        }

        let hiddenDisclosures: Set<DashboardDisclosure>
        if let rawVisibility = defaults.dictionary(
            forKey: disclosureVisibilityDefaultsKey
        ) {
            hiddenDisclosures = Set(
                DashboardDisclosure.allCases.filter { disclosure in
                    (rawVisibility[disclosure.rawValue] as? Bool) == false
                }
            )
        } else {
            hiddenDisclosures = []
        }

        return DashboardLayout(
            order: order,
            expandedSections: expandedSections,
            hiddenSections: hiddenSections,
            hiddenDisclosures: hiddenDisclosures
        )
    }

    func save(to defaults: UserDefaults) {
        defaults.set(order.map(\.rawValue), forKey: Self.orderDefaultsKey)
        defaults.set(
            Dictionary(
                uniqueKeysWithValues: DashboardSection.allCases.map {
                    ($0.rawValue, expandedSections.contains($0))
                }
            ),
            forKey: Self.expandedDefaultsKey
        )
        defaults.set(
            Dictionary(
                uniqueKeysWithValues: DashboardSection.allCases.map {
                    ($0.rawValue, !hiddenSections.contains($0))
                }
            ),
            forKey: Self.visibilityDefaultsKey
        )
        defaults.set(
            Dictionary(
                uniqueKeysWithValues: DashboardDisclosure.allCases.map {
                    ($0.rawValue, !hiddenDisclosures.contains($0))
                }
            ),
            forKey: Self.disclosureVisibilityDefaultsKey
        )
    }

    mutating func move(_ section: DashboardSection, to targetIndex: Int) {
        guard let sourceIndex = order.firstIndex(of: section) else {
            return
        }
        let boundedTarget = min(max(0, targetIndex), order.count - 1)
        guard sourceIndex != boundedTarget else {
            return
        }
        order.remove(at: sourceIndex)
        order.insert(section, at: min(boundedTarget, order.count))
    }

    mutating func setExpanded(
        _ section: DashboardSection,
        expanded: Bool
    ) {
        if expanded {
            expandedSections.insert(section)
        } else {
            expandedSections.remove(section)
        }
    }

    func isVisible(_ section: DashboardSection) -> Bool {
        !hiddenSections.contains(section)
    }

    mutating func setVisible(
        _ section: DashboardSection,
        visible: Bool
    ) {
        if visible {
            hiddenSections.remove(section)
        } else {
            hiddenSections.insert(section)
        }
    }

    func isVisible(_ disclosure: DashboardDisclosure) -> Bool {
        !hiddenDisclosures.contains(disclosure)
    }

    mutating func setVisible(
        _ disclosure: DashboardDisclosure,
        visible: Bool
    ) {
        if visible {
            hiddenDisclosures.remove(disclosure)
        } else {
            hiddenDisclosures.insert(disclosure)
        }
    }

    mutating func setOrder(_ proposedOrder: [DashboardSection]) {
        order = Self.normalizedOrder(proposedOrder)
    }

    mutating func reset() {
        self = .default
    }

    private static func normalizedOrder(
        _ proposed: [DashboardSection]
    ) -> [DashboardSection] {
        var seen = Set<DashboardSection>()
        var normalized = proposed.filter { seen.insert($0).inserted }
        guard !normalized.isEmpty else {
            return defaultOrder
        }

        for (defaultIndex, section) in defaultOrder.enumerated()
        where !seen.contains(section) {
            let precedingAnchor = defaultOrder[..<defaultIndex]
                .reversed()
                .first(where: seen.contains)
            let followingAnchor = defaultOrder
                .dropFirst(defaultIndex + 1)
                .first(where: seen.contains)

            if let precedingAnchor,
               let anchorIndex = normalized.firstIndex(of: precedingAnchor) {
                normalized.insert(section, at: anchorIndex + 1)
            } else if let followingAnchor,
                      let anchorIndex = normalized.firstIndex(of: followingAnchor) {
                normalized.insert(section, at: anchorIndex)
            } else {
                normalized.append(section)
            }
            seen.insert(section)
        }

        return normalized
    }
}

enum DashboardSectionExpansionPolicy {
    struct Resolution: Equatable {
        let isExpanded: Bool
        let canCollapse: Bool
    }

    static func resolve(
        section: DashboardSection,
        preferredExpanded: Bool,
        resetCreditStatus: ResetCreditProtectionStatus,
        hasUnresolvedResetCreditAttempt: Bool,
        requiresUpdateAttention: Bool = false
    ) -> Resolution {
        let forced = forcesExpansion(
            of: section,
            resetCreditStatus: resetCreditStatus,
            hasUnresolvedResetCreditAttempt:
                hasUnresolvedResetCreditAttempt,
            requiresUpdateAttention: requiresUpdateAttention
        )
        return Resolution(
            isExpanded: preferredExpanded || forced,
            canCollapse: !forced
        )
    }

    static func forcesExpansion(
        of section: DashboardSection,
        resetCreditStatus: ResetCreditProtectionStatus,
        hasUnresolvedResetCreditAttempt: Bool,
        requiresUpdateAttention: Bool = false
    ) -> Bool {
        if section == .updates {
            return requiresUpdateAttention
        }
        guard section == .resetCredits else {
            return false
        }
        if hasUnresolvedResetCreditAttempt {
            return true
        }
        switch resetCreditStatus {
        case .blocked, .missed, .using, .reconciling:
            return true
        default:
            return false
        }
    }
}

enum DashboardSectionVisibilityPolicy {
    struct Resolution: Equatable {
        let isVisible: Bool
        let canHide: Bool
    }

    static func resolve(
        section: DashboardSection,
        preferredVisible: Bool,
        resetCreditStatus: ResetCreditProtectionStatus,
        hasUnresolvedResetCreditAttempt: Bool,
        requiresUpdateAttention: Bool = false
    ) -> Resolution {
        let forced = DashboardSectionExpansionPolicy.forcesExpansion(
            of: section,
            resetCreditStatus: resetCreditStatus,
            hasUnresolvedResetCreditAttempt:
                hasUnresolvedResetCreditAttempt,
            requiresUpdateAttention: requiresUpdateAttention
        )
        return Resolution(
            isVisible: preferredVisible || forced,
            canHide: !forced
        )
    }
}
