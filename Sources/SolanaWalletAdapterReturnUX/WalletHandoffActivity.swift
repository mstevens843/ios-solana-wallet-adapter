// Live Activities are iOS-only. ActivityKit *imports* on macOS but its
// request/update/end APIs are macOS-unavailable, so guard on os(iOS), not
// canImport(ActivityKit).
#if os(iOS)
import Foundation
import ActivityKit

/// Shared Live Activity attributes for the wallet hand-off "tap-to-return" pill.
///
/// Import this from BOTH the app (to start/update/end the activity via
/// ``WalletHandoffActivityController``) and the app's Widget Extension (to render
/// the lock-screen / Dynamic Island UI), so there is a single source of truth.
///
/// The widget should set its tap target / `widgetURL` to ``returnURL`` so one tap
/// foregrounds the dApp.
@available(iOS 16.2, *)
public struct WalletHandoffAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var status: WalletHandoffStatus
        public var detail: String?

        public init(status: WalletHandoffStatus, detail: String? = nil) {
            self.status = status
            self.detail = detail
        }
    }

    /// Display name of the wallet the user was sent to (e.g. "Jupiter Mobile").
    public let walletName: String
    /// Display name of the calling dApp (e.g. "Agentic").
    public let dappName: String
    /// Deep link the widget opens on tap to bring the dApp back to the foreground.
    public let returnURL: URL

    public init(walletName: String, dappName: String, returnURL: URL) {
        self.walletName = walletName
        self.dappName = dappName
        self.returnURL = returnURL
    }
}

/// Starts / updates / ends the wallet hand-off Live Activity. Call ``start(...)``
/// immediately before opening the wallet, ``update(_:detail:)`` when the result
/// arrives (on app foreground or via an ActivityKit push on on-chain confirm),
/// and ``end()`` to dismiss.
@available(iOS 16.2, *)
@MainActor
public final class WalletHandoffActivityController {
    private var activity: Activity<WalletHandoffAttributes>?

    public init() {}

    /// True if the user has Live Activities enabled for this app.
    public var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Start the hand-off pill. Safe no-op if Live Activities are disabled or one
    /// is already active. Returns whether an activity was started.
    @discardableResult
    public func start(walletName: String, dappName: String, returnURL: URL, detail: String? = nil) -> Bool {
        guard activity == nil, areActivitiesEnabled else { return false }
        let attributes = WalletHandoffAttributes(walletName: walletName, dappName: dappName, returnURL: returnURL)
        let state = WalletHandoffAttributes.ContentState(
            status: .waiting,
            detail: detail ?? "Approve in \(walletName), then tap to return to \(dappName)."
        )
        activity = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil)
        )
        return activity != nil
    }

    /// Update the pill's status (e.g. to `.signed` after the result arrives).
    public func update(_ status: WalletHandoffStatus, detail: String? = nil) async {
        guard let activity else { return }
        await activity.update(ActivityContent(
            state: WalletHandoffAttributes.ContentState(status: status, detail: detail),
            staleDate: nil
        ))
    }

    /// End and dismiss the activity.
    public func end(finalStatus: WalletHandoffStatus = .signed, detail: String? = nil) async {
        guard let activity else { return }
        await activity.end(
            ActivityContent(state: WalletHandoffAttributes.ContentState(status: finalStatus, detail: detail), staleDate: nil),
            dismissalPolicy: .immediate
        )
        self.activity = nil
    }
}
#endif
