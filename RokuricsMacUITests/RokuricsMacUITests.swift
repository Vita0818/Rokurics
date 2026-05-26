//
//  RokuricsMacUITests.swift
//  RokuricsMacUITests
//
//  Created by Vita on 2026/5/10.
//

import XCTest

final class RokuricsMacUITests: XCTestCase {
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testIPhoneConnectionStartPairingPublishesCodeAndEnablesCopy() throws {
        let app = makeIsolatedApp()
        app.launch()

        let sidebarButton = app.buttons["mac-sidebar-iphone-connection"]
        XCTAssertTrue(sidebarButton.waitForExistence(timeout: 8), "iPhone connection sidebar button should exist")
        sidebarButton.click()

        let startButton = app.buttons["mac-iphone-start-pairing-button"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 8), "Start pairing button should exist in the real Mac UI")
        XCTAssertTrue(startButton.isEnabled, "Start pairing button must be enabled in fresh unpaired UI state")
        startButton.click()

        let pairingCode = app.descendants(matching: .any)["mac-iphone-pairing-code"]
        guard pairingCode.waitForExistence(timeout: 8) else {
            XCTFail("Pairing code should be published into the real UI.\n\(app.debugDescription)")
            return
        }
        let pairingCodeText = pairingCode.label.isEmpty ? (pairingCode.value as? String ?? "") : pairingCode.label
        XCTAssertNotNil(
            pairingCodeText.range(of: #"^\d{6}$"#, options: .regularExpression),
            "Pairing code should be a six digit code"
        )

        let copyButton = app.buttons["mac-iphone-copy-pairing-info-button"]
        XCTAssertTrue(copyButton.waitForExistence(timeout: 2), "Copy pairing info button should remain in the real UI")
        XCTAssertTrue(copyButton.isEnabled, "Copy pairing info button should become enabled after payload publication")
    }

    private func makeIsolatedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["ROKURICS_UI_TEST_MODE"] = "1"
        app.launchEnvironment["ROKURICS_UI_TEST_STORAGE_NAMESPACE"] = UUID().uuidString
        app.launchEnvironment["ROKURICS_UI_TEST_RECEIVER_PORT"] = "0"
        app.launchEnvironment["ROKURICS_UI_TEST_HOST"] = "127.0.0.1"
        return app
    }

    private func waitForDiagnostics(
        at url: URL,
        containing phases: [String],
        timeout: TimeInterval = 6
    ) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let text = try? String(contentsOf: url, encoding: .utf8),
               phases.allSatisfy({ text.contains($0) }) {
                return text
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return try String(contentsOf: url, encoding: .utf8)
    }
}
