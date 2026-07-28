import AppKit
import XCTest
@testable import CodexRadarSentinel

final class DashboardTextSizeTests: XCTestCase {
    func testModelIQColumnsFitRepresentativeValuesAtEveryTextSize() {
        for textSize in DashboardTextSize.allCases {
            let metrics = textSize.metrics
            let valueFont = NSFont.monospacedSystemFont(
                ofSize: metrics.label,
                weight: .medium
            )
            let headerFont = NSFont.systemFont(
                ofSize: metrics.caption,
                weight: .semibold
            )

            assertColumn(
                width: metrics.modelIQScoreColumnWidth,
                values: [("103.1", valueFont), ("IQ", headerFont)],
                textSize: textSize
            )
            assertColumn(
                width: metrics.modelIQResultColumnWidth,
                values: [("999/1000", valueFont), ("Passed", headerFont)],
                textSize: textSize
            )
            assertColumn(
                width: metrics.modelIQRatingColumnWidth,
                values: [("10.0", valueFont), ("Rating", headerFont)],
                textSize: textSize
            )
        }
    }

    private func assertColumn(
        width: CGFloat,
        values: [(String, NSFont)],
        textSize: DashboardTextSize,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for (value, font) in values {
            let measuredWidth = ceil(
                (value as NSString).size(withAttributes: [.font: font]).width
            )
            XCTAssertGreaterThanOrEqual(
                width,
                measuredWidth + 2,
                "\(textSize.label) column does not fit \(value)",
                file: file,
                line: line
            )
        }
    }
}
