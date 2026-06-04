import SwiftUI

struct HomeView: View {
    let publicKey: String
    let walletLabel: String
    let status: String
    let isBusy: Bool

    let onSignMessage: () -> Void
    let onSignTransaction: () -> Void
    let onSignAndSend: () -> Void
    let onSignAll: () -> Void
    let onGetCapabilities: () -> Void
    let onDisconnect: () -> Void
    let onDeleteAccount: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

                VStack(spacing: 18) {
                    Text("MWA Example App")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)

                    Text("\(HomeView.shortAddress(publicKey)) (\(walletLabel))")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }

                VStack(spacing: 12) {
                    DemoActionButton(title: "Sign Message", style: .primary, isBusy: isBusy, action: onSignMessage)
                    DemoActionButton(title: "Sign Transaction", style: .primary, isBusy: isBusy, action: onSignTransaction)
                    DemoActionButton(title: "Sign & Send", style: .primary, isBusy: isBusy, action: onSignAndSend)
                    DemoActionButton(title: "Sign All (2 tx)", style: .primary, isBusy: isBusy, action: onSignAll)
                    DemoActionButton(title: "Get Capabilities", style: .muted, isBusy: isBusy, action: onGetCapabilities)
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)

                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 14)

                VStack(spacing: 12) {
                    DemoActionButton(title: "Disconnect", style: .warning, isBusy: isBusy, action: onDisconnect)
                    DemoActionButton(title: "Delete Account", style: .destructive, isBusy: isBusy, action: onDeleteAccount)
                }
                .padding(.horizontal, 32)
                .padding(.top, 14)

                Spacer()
                Spacer()
        }
    }

    private var statusText: String {
        status.isEmpty ? "Connected — choose an action" : status
    }

    static func shortAddress(_ key: String) -> String {
        guard key.count > 9 else { return key }
        return "\(key.prefix(4))…\(key.suffix(4))"
    }
}

private struct DemoActionButton: View {
    enum Style {
        case primary, muted, warning, destructive

        var background: Color {
            switch self {
            case .primary: return Color(red: 0.18, green: 0.55, blue: 0.96)
            case .muted: return Color(red: 0.40, green: 0.50, blue: 0.70)
            case .warning: return Color(red: 0.85, green: 0.45, blue: 0.18)
            case .destructive: return Color(red: 0.78, green: 0.20, blue: 0.20)
            }
        }
    }

    let title: String
    let style: Style
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(style.background.opacity(isBusy ? 0.55 : 1.0))
                .cornerRadius(8)
        }
        .disabled(isBusy)
    }
}

/// One reusable toast for every wallet action: green on success, red on
/// failure, and a white "Signed in with Solana" pill (`.siws`) for the sign-in
/// flow. Routed through `WalletDemoView.showToast` so the user gets a clear
/// success/fail signal for each action.
struct DemoToast: Equatable, Identifiable {
    enum Style { case success, failure, siws }

    let id = UUID()
    let message: String
    let style: Style
}

struct DemoToastView: View {
    let toast: DemoToast

    var body: some View {
        HStack(spacing: 10) {
            icon
            Text(toast.message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(textColor)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Capsule().fill(background))
        .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 2)
    }

    @ViewBuilder private var icon: some View {
        switch toast.style {
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
        case .failure:
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
        case .siws:
            ZStack {
                Circle().fill(Color.black).frame(width: 22, height: 22)
                Image(systemName: "hexagon.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }

    private var background: Color {
        switch toast.style {
        case .success: return Color(red: 0.16, green: 0.62, blue: 0.36)
        case .failure: return Color(red: 0.80, green: 0.23, blue: 0.23)
        case .siws: return .white
        }
    }

    private var textColor: Color {
        toast.style == .siws ? .black : .white
    }
}
