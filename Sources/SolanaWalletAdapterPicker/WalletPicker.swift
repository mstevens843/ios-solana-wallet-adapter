import Foundation

/// Top-level convenience namespace for the picker module.
public enum WalletPicker {
    /// The `LSApplicationQueriesSchemes` Info.plist entries an app needs to
    /// declare so the picker can probe wallet installation status. Apple won't
    /// let `UIApplication.canOpenURL` succeed otherwise.
    ///
    /// ```xml
    /// <key>LSApplicationQueriesSchemes</key>
    /// <array>
    ///     <string>phantom</string>
    ///     <string>solflare</string>
    ///     <string>backpack</string>
    /// </array>
    /// ```
    ///
    /// Jupiter Mobile is reachable via WalletConnect, not a native scheme, so
    /// it is intentionally not listed here.
    public static let requiredQuerySchemes: [String] = ["phantom", "solflare", "backpack"]
}
