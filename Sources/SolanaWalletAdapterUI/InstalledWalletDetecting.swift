import Foundation

/// Probes whether a wallet app is installed on the device based on its custom
/// URL scheme. Wraps `UIApplication.canOpenURL(_:)` so callers (the picker, the
/// reconnect helper) can swap in stubs for tests.
///
/// On iOS, `canOpenURL` only succeeds for schemes the host app has declared in
/// `LSApplicationQueriesSchemes`. See the picker docs for the four entries an
/// app must add to use the bundled adapter set.
public protocol InstalledWalletDetecting: Sendable {
    func isInstalled(scheme: String) -> Bool
}

public struct StubInstalledWalletDetector: InstalledWalletDetecting {
    public let installed: Set<String>

    public init(installed: Set<String>) {
        self.installed = installed
    }

    public func isInstalled(scheme: String) -> Bool {
        installed.contains(scheme)
    }
}

#if canImport(UIKit)
import UIKit

@MainActor
public struct UIApplicationInstalledWalletDetector: InstalledWalletDetecting {
    private let application: UIApplication

    public init(application: UIApplication = .shared) {
        self.application = application
    }

    public func isInstalled(scheme: String) -> Bool {
        guard let url = URL(string: "\(scheme)://") else { return false }
        return application.canOpenURL(url)
    }
}

@MainActor
public enum InstalledWalletDetector {
    public static let `default`: any InstalledWalletDetecting = UIApplicationInstalledWalletDetector()
}
#else
public enum InstalledWalletDetector {
    public static let `default`: any InstalledWalletDetecting = StubInstalledWalletDetector(installed: [])
}
#endif
