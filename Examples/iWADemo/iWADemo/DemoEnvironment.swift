import Foundation

/// Builds the `[String: String]` environment the demo hands to
/// `WalletAdapterServiceConfiguration.fromEnvironment(_:)`.
///
/// On a physical device an app launched via `devicectl` does NOT inherit the Mac
/// shell environment, so `ProcessInfo.processInfo.environment` carries none of
/// our keys. The build-time-generated `IWASecrets.values` (from the gitignored
/// root `.env`, via `scripts/iwa-env.sh gen-device`) is the device floor. The
/// live process environment overrides per key, so a simulator run or an Xcode
/// scheme env var still wins for a quick override without regenerating secrets.
enum DemoEnvironment {
    static func resolved() -> [String: String] {
        var merged = IWASecrets.values
        for (key, value) in ProcessInfo.processInfo.environment {
            merged[key] = value
        }
        return merged
    }
}
