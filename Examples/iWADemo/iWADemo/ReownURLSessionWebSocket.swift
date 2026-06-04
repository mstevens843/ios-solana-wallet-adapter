import Foundation
import WalletConnectNetworking

/// `WebSocketConnecting` over `URLSessionWebSocketTask`, so the Reown relay needs
/// no third-party socket library (the SDK's own example uses Starscream; this
/// avoids that dependency). Reown drives `connect()/write()/disconnect()` and
/// reads back via the `onConnect`/`onText`/`onDisconnect` callbacks.
final class ReownURLSessionWebSocket: NSObject, WebSocketConnecting, URLSessionWebSocketDelegate, @unchecked Sendable {
    var request: URLRequest
    var isConnected: Bool = false
    var onConnect: (() -> Void)?
    var onDisconnect: ((Error?) -> Void)?
    var onText: ((String) -> Void)?

    private var task: URLSessionWebSocketTask?
    private lazy var session: URLSession = URLSession(
        configuration: .default,
        delegate: self,
        delegateQueue: nil
    )

    init(request: URLRequest) {
        self.request = request
        super.init()
    }

    func connect() {
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
        receive()
    }

    func disconnect() {
        isConnected = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    func write(string: String, completion: (() -> Void)?) {
        task?.send(.string(string)) { _ in completion?() }
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                if case let .string(text) = message {
                    self.onText?(text)
                } else if case let .data(data) = message, let text = String(data: data, encoding: .utf8) {
                    self.onText?(text)
                }
                self.receive()
            case .failure(let error):
                self.isConnected = false
                self.onDisconnect?(error)
            }
        }
    }

    // MARK: URLSessionWebSocketDelegate

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        isConnected = true
        onConnect?()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        isConnected = false
        onDisconnect?(nil)
    }
}

/// Builds `ReownURLSessionWebSocket`s for the Reown relay.
struct ReownURLSessionWebSocketFactory: WebSocketFactory {
    func create(with url: URL) -> WebSocketConnecting {
        ReownURLSessionWebSocket(request: URLRequest(url: url))
    }
}
