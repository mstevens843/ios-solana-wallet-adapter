import Foundation

@MainActor
public protocol WalletURLOpening: Sendable {
    func openWalletURL(_ url: URL) async -> Bool
}

public struct ClosureWalletURLOpener: WalletURLOpening {
    private let open: @MainActor @Sendable (URL) async -> Bool

    public init(_ open: @escaping @MainActor @Sendable (URL) async -> Bool) {
        self.open = open
    }

    public func openWalletURL(_ url: URL) async -> Bool {
        await open(url)
    }
}

#if canImport(SwiftUI)
import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
public struct SwiftUIWalletURLOpener: WalletURLOpening {
    private let openURL: OpenURLAction

    public init(openURL: OpenURLAction) {
        self.openURL = openURL
    }

    public func openWalletURL(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            openURL(url) { accepted in
                continuation.resume(returning: accepted)
            }
        }
    }
}
#endif

#if canImport(UIKit)
import UIKit

@available(iOS 16.0, *)
public struct UIKitWalletURLOpener: WalletURLOpening {
    private let application: UIApplication

    public init(application: UIApplication = .shared) {
        self.application = application
    }

    public func openWalletURL(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            application.open(url, options: [:]) { accepted in
                continuation.resume(returning: accepted)
            }
        }
    }
}
#endif
