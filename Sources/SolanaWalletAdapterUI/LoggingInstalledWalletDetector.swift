import Foundation
import SolanaWalletAdapter

/// `InstalledWalletDetecting` decorator that emits deterministic `[iWA]` logs for
/// every install probe, then returns the wrapped detector's result unchanged.
///
/// Inject it at the `walletPickerSheet(detector:)` seam (or wherever a detector
/// is supplied) to make the "is this wallet installed?" decision visible in the
/// logs. The most useful diagnostic is `declared_in_lsaqs`: on iOS,
/// `UIApplication.canOpenURL` silently returns `false` for any scheme missing
/// from `LSApplicationQueriesSchemes`, which presents as a false "not installed".
/// When a probe returns `false` *and* the scheme is not declared, this emits a
/// `STEP_FAIL_SCHEME_UNDECLARED` line with a fix hint.
public struct LoggingInstalledWalletDetector: InstalledWalletDetecting {
    public static let component = "InstalledWalletDetector"

    private let inner: any InstalledWalletDetecting
    private let logger: any WalletAdapterLogger
    private let logLevel: WalletAdapterLogLevel
    private let declaredQuerySchemes: Set<String>

    /// - Parameters:
    ///   - inner: the real detector to delegate to (e.g. `InstalledWalletDetector.default`).
    ///   - logger: sink for the structured probe events.
    ///   - logLevel: gate; `.off` disables logging (probe still delegates).
    ///   - declaredQuerySchemes: the schemes declared in `LSApplicationQueriesSchemes`.
    ///     Defaults to reading `Bundle.main` at init; injectable for tests.
    public init(
        wrapping inner: any InstalledWalletDetecting,
        logger: any WalletAdapterLogger,
        logLevel: WalletAdapterLogLevel = .info,
        declaredQuerySchemes: Set<String>? = nil
    ) {
        self.inner = inner
        self.logger = logger
        self.logLevel = logLevel
        self.declaredQuerySchemes = declaredQuerySchemes ?? Self.readDeclaredQuerySchemes()
    }

    public func isInstalled(scheme: String) -> Bool {
        let result = inner.isInstalled(scheme: scheme)
        guard logLevel != .off else { return result }

        let normalizedScheme = scheme.lowercased()
        let declared = declaredQuerySchemes.contains(normalizedScheme)

        log("STEP_1_PROBE", "INFO", .info, "probing wallet install state", [
            "wallet": scheme,
            "scheme": scheme,
            "probe_url": "\(scheme)://",
            "declared_in_lsaqs": "\(declared)",
        ])
        log("STEP_2_RESULT", "INFO", .info, "wallet install probe result", [
            "wallet": scheme,
            "can_open_url": "\(result)",
            "installed": "\(result)",
        ])
        if !result && !declared {
            log("STEP_FAIL_SCHEME_UNDECLARED", "FAIL", .error, "scheme not declared for canOpenURL", [
                "wallet": scheme,
                "scheme": scheme,
                "reason": "scheme_not_in_LSApplicationQueriesSchemes",
                "fix_hint": "Add \(scheme) to LSApplicationQueriesSchemes in Info.plist",
            ])
        }
        return result
    }

    private func log(
        _ step: String,
        _ phase: String,
        _ level: WalletAdapterLogLevel,
        _ message: String,
        _ metadata: [String: String]
    ) {
        guard logLevel != .off, level <= logLevel else { return }
        logger.log(WalletAdapterLogEvent(
            component: Self.component,
            method: "isInstalled",
            step: step,
            phase: phase,
            message: message,
            metadata: metadata
        ))
    }

    private static func readDeclaredQuerySchemes() -> Set<String> {
        guard let declared = Bundle.main.object(forInfoDictionaryKey: "LSApplicationQueriesSchemes") as? [String] else {
            return []
        }
        return Set(declared.map { $0.lowercased() })
    }
}
