import XCTest
@testable import CodexRadarCore

final class ResetCreditTests: XCTestCase {
    func testReadsAccessTokenFromNestedAuthJSON() throws {
        let data = Data("""
        {
          "tokens": {
            "access_token": "access-token-value",
            "refresh_token": "refresh-token-value"
          }
        }
        """.utf8)

        XCTAssertEqual(try ResetCreditClient.accessToken(fromAuthData: data), "access-token-value")
    }

    func testDecodesResetCreditResponseAndRedactsIDs() throws {
        let checkedAt = Date(timeIntervalSince1970: 1_783_000_000)
        let snapshot = try ResetCreditSnapshot(responseData: Data("""
        {
          "credits": [
            {
              "id": "credit_1234567890abcdef",
              "reset_type": "codex_rate_limits",
              "status": "available",
              "granted_at": "2026-06-12T02:35:09.477917Z",
              "expires_at": "2026-07-12T02:35:09.477917Z",
              "redeem_started_at": null,
              "redeemed_at": null,
              "profile_image_url": "https://example.com/profile.png",
              "profile_user_id": "sensitive-user-id",
              "title": "Full reset (Weekly + 5 hr)"
            }
          ],
          "available_count": 1,
          "total_earned_count": 1
        }
        """.utf8), checkedAt: checkedAt)

        XCTAssertEqual(snapshot.checkedAt, checkedAt)
        XCTAssertEqual(snapshot.effectiveAvailableCount, 1)
        XCTAssertEqual(snapshot.credits.count, 1)
        XCTAssertEqual(snapshot.credits.first?.idSuffix, "abcdef")
        XCTAssertEqual(snapshot.credits.first?.title, "Full reset (Weekly + 5 hr)")
        XCTAssertEqual(snapshot.credits.first?.status, "available")
        XCTAssertEqual(snapshot.credits.first?.resetType, "codex_rate_limits")
        XCTAssertNotNil(snapshot.credits.first?.grantedAt)
        XCTAssertNotNil(snapshot.credits.first?.expiresAt)
    }

    func testSortsAvailableCreditsBySoonestExpiry() throws {
        let snapshot = try ResetCreditSnapshot(responseData: Data("""
        {
          "credits": [
            {
              "id": "late-credit",
              "status": "available",
              "granted_at": "2026-06-10T00:00:00Z",
              "expires_at": "2026-07-20T00:00:00Z",
              "title": "Late"
            },
            {
              "id": "used-credit",
              "status": "redeemed",
              "granted_at": "2026-06-10T00:00:00Z",
              "expires_at": "2026-07-10T00:00:00Z",
              "redeemed_at": "2026-06-20T00:00:00Z",
              "title": "Used"
            },
            {
              "id": "soon-credit",
              "status": "available",
              "granted_at": "2026-06-10T00:00:00Z",
              "expires_at": "2026-07-12T00:00:00Z",
              "title": "Soon"
            }
          ]
        }
        """.utf8))

        XCTAssertEqual(snapshot.credits.map(\.title), ["Soon", "Late", "Used"])
    }
}
