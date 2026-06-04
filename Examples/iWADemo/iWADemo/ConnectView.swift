import SwiftUI

/// Pre-connect entry point. Renders the "Connect Wallet" primary button and,
/// when a cached session can be resumed, a green "Reconnect (Cached)" button
/// below it with a "Cached session found: …" caption.
struct ConnectView: View {
    let status: String
    let isBusy: Bool
    let canReconnect: Bool
    let cachedPubkeyCaption: String?
    let onConnect: () -> Void
    let onReconnect: () -> Void

    init(
        status: String,
        isBusy: Bool,
        canReconnect: Bool = false,
        cachedPubkeyCaption: String? = nil,
        onConnect: @escaping () -> Void,
        onReconnect: @escaping () -> Void = {}
    ) {
        self.status = status
        self.isBusy = isBusy
        self.canReconnect = canReconnect
        self.cachedPubkeyCaption = cachedPubkeyCaption
        self.onConnect = onConnect
        self.onReconnect = onReconnect
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 8) {
                Text("iWA Example App")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                Text("iOS Solana Wallet Adapter Demo")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }

            VStack(spacing: 12) {
                ConnectPrimaryButton(title: "Connect Wallet", isBusy: isBusy, action: onConnect)
                if canReconnect {
                    ConnectReconnectButton(isBusy: isBusy, action: onReconnect)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)

            Text(statusText)
                .font(.system(size: 12))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 14)

            if let caption = cachedPubkeyCaption {
                CachedSessionPill(text: caption)
                    .padding(.top, 18)
            }

            Spacer()
            Spacer()
        }
    }

    private var statusText: String {
        switch status {
        case "", "Ready": return "Tap Connect to link your wallet"
        default: return status
        }
    }
}

private struct ConnectPrimaryButton: View {
    let title: String
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color(red: 0.18, green: 0.55, blue: 0.96).opacity(isBusy ? 0.55 : 1.0))
                .cornerRadius(8)
        }
        .disabled(isBusy)
    }
}

private struct ConnectReconnectButton: View {
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Reconnect (Cached)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color(red: 0.18, green: 0.66, blue: 0.40).opacity(isBusy ? 0.55 : 1.0))
                .cornerRadius(8)
        }
        .disabled(isBusy)
    }
}

private struct CachedSessionPill: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .foregroundColor(.white.opacity(0.7))
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
    }
}
