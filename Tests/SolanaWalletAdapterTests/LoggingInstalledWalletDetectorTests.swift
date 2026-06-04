import XCTest
import SolanaWalletAdapter
import SolanaWalletAdapterUI

final class LoggingInstalledWalletDetectorTests: XCTestCase {
    func testProbeLogsResultWhenInstalledAndDeclared() {
        let logger = RecordingLogger()
        let detector = LoggingInstalledWalletDetector(
            wrapping: StubInstalledWalletDetector(installed: ["phantom"]),
            logger: logger,
            logLevel: .info,
            declaredQuerySchemes: ["phantom", "solflare", "backpack"]
        )

        XCTAssertTrue(detector.isInstalled(scheme: "phantom"))

        let events = logger.events(component: "InstalledWalletDetector", method: "isInstalled")
        XCTAssertEqual(events.map(\.step), ["STEP_1_PROBE", "STEP_2_RESULT"])
        XCTAssertEqual(events.first { $0.step == "STEP_1_PROBE" }?.metadata["declared_in_lsaqs"], "true")
        XCTAssertEqual(events.first { $0.step == "STEP_2_RESULT" }?.metadata["installed"], "true")
    }

    func testUndeclaredSchemeEmitsFailureHint() throws {
        let logger = RecordingLogger()
        let detector = LoggingInstalledWalletDetector(
            wrapping: StubInstalledWalletDetector(installed: []),
            logger: logger,
            logLevel: .info,
            declaredQuerySchemes: []
        )

        XCTAssertFalse(detector.isInstalled(scheme: "phantom"))

        let fail = try XCTUnwrap(logger.events().first { $0.step == "STEP_FAIL_SCHEME_UNDECLARED" })
        XCTAssertEqual(fail.metadata["reason"], "scheme_not_in_LSApplicationQueriesSchemes")
        XCTAssertEqual(fail.phase, "FAIL")
        XCTAssertEqual(fail.metadata["wallet"], "phantom")
    }

    func testInstalledButUndeclaredDoesNotEmitFailure() {
        // canOpenURL true even though not in our declared set: no false alarm.
        let logger = RecordingLogger()
        let detector = LoggingInstalledWalletDetector(
            wrapping: StubInstalledWalletDetector(installed: ["phantom"]),
            logger: logger,
            logLevel: .info,
            declaredQuerySchemes: []
        )

        XCTAssertTrue(detector.isInstalled(scheme: "phantom"))
        XCTAssertFalse(logger.events().contains { $0.step == "STEP_FAIL_SCHEME_UNDECLARED" })
    }

    func testOffLevelEmitsNothingButStillDelegates() {
        let logger = RecordingLogger()
        let detector = LoggingInstalledWalletDetector(
            wrapping: StubInstalledWalletDetector(installed: ["backpack"]),
            logger: logger,
            logLevel: .off,
            declaredQuerySchemes: []
        )

        XCTAssertTrue(detector.isInstalled(scheme: "backpack"))
        XCTAssertTrue(logger.events().isEmpty)
    }
}
