#if canImport(UIKit)
import Foundation
import UIKit

/// Default `JWAReturnOpening` for a wallet's main app: opens the dApp's
/// `redirect_link` via `UIApplication.open`, foregrounding the calling app.
///
/// Not available in app extensions (no `UIApplication.shared`); a wallet running
/// the handler from an extension should provide its own opener.
public struct UIApplicationReturnOpener: JWAReturnOpening {
    public init() {}

    @MainActor
    public func open(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { success in
                continuation.resume(returning: success)
            }
        }
    }
}
#endif
