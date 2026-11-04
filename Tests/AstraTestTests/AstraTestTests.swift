import XCTest
@testable import AstraTest

final class AstraTestTests: XCTestCase {
    func testRingKeepsTheNewest() {
        let r = Ring<Int>(cap: 3)
        (1...5).forEach { r.push($0) }
        XCTAssertEqual(r.all(), [3, 4, 5])
    }

    func testRejectsBadKeys() {
        AstraTest.start(key: "nope")
        XCTAssertFalse(AstraTest.started)
    }

    func testNetworkRecordDropsQuery() {
        var r = URLRequest(url: URL(string: "https://api.example.com/v1/cart?token=secret#x")!)
        r.httpMethod = "POST"
        NetworkCapture.record(r, status: 500, since: Date())
        let last = NetworkCapture.calls.all().last
        XCTAssertEqual(last?.url, "https://api.example.com/v1/cart")
        XCTAssertEqual(last?.status, 500)
        XCTAssertEqual(last?.method, "POST")
    }

    /// Sends a real report when ASTRA_E2E_KEY is set (to a demo project), so the payload is checked by the server.
    func testSendsARealReport() throws {
        guard let key = ProcessInfo.processInfo.environment["ASTRA_E2E_KEY"] else { throw XCTSkip("Set ASTRA_E2E_KEY to run") }
        AstraTest.start(key: key, options: .init(appVersion: "9.9.0", build: "1", showButton: false, shakeToReport: false))
        AstraTest.identify(email: "sdk-e2e@astratest.dev", name: "SDK e2e")
        AstraTest.setScreen("SDK self-test")
        AstraTest.log("Checkout failed: promo returned percent", level: "error")
        let done = expectation(description: "sent")
        var ref: String?
        AstraTest.send(description: "Apple SDK end-to-end check: promo code shows applied but the total doesn't change.") { r in
            if case .success(let s) = r { ref = s.ref } else if case .failure(let e) = r { XCTFail(e.localizedDescription) }
            done.fulfill()
        }
        wait(for: [done], timeout: 90)
        XCTAssertNotNil(ref)
        print("SENT", ref ?? "")
    }
}
