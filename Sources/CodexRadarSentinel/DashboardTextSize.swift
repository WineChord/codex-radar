import CoreGraphics
import Foundation

enum DashboardTextSize: String, CaseIterable, Identifiable {
    case medium
    case large
    case extraLarge

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .medium:
            return "M"
        case .large:
            return "L"
        case .extraLarge:
            return "XL"
        }
    }

    var metrics: Metrics {
        switch self {
        case .medium:
            return Metrics(
                width: 350,
                height: 440,
                headerIcon: 18,
                headerTitle: 14,
                body: 13,
                label: 12,
                caption: 11,
                section: 12,
                badge: 12,
                tileValue: 20,
                quotaTileHeight: 68,
                toolbarButtonSize: 28
            )
        case .large:
            return Metrics(
                width: 360,
                height: 460,
                headerIcon: 19,
                headerTitle: 15,
                body: 14,
                label: 13,
                caption: 12,
                section: 13,
                badge: 13,
                tileValue: 22,
                quotaTileHeight: 74,
                toolbarButtonSize: 30
            )
        case .extraLarge:
            return Metrics(
                width: 380,
                height: 500,
                headerIcon: 20,
                headerTitle: 16,
                body: 15,
                label: 14,
                caption: 13,
                section: 14,
                badge: 14,
                tileValue: 24,
                quotaTileHeight: 80,
                toolbarButtonSize: 32
            )
        }
    }

    struct Metrics {
        let width: CGFloat
        let height: CGFloat
        let headerIcon: CGFloat
        let headerTitle: CGFloat
        let body: CGFloat
        let label: CGFloat
        let caption: CGFloat
        let section: CGFloat
        let badge: CGFloat
        let tileValue: CGFloat
        let quotaTileHeight: CGFloat
        let toolbarButtonSize: CGFloat
    }
}
