import Foundation
import SolanaWalletAdapter

@MainActor
final class DemoLogRecorder: ObservableObject {
    @Published private(set) var lines: [String] = []
    private let sink = LockedLogSink()

    nonisolated func logger(prefix: String = "[iWA Demo]") -> WalletAdapterLogger {
        sink.prefix = prefix
        sink.onLine = { [weak self] line in
            Task { @MainActor in
                self?.lines.append(line)
            }
        }
        return sink
    }

    func clear() {
        lines.removeAll()
    }

    var text: String {
        lines.joined(separator: "\n")
    }
}

private final class LockedLogSink: WalletAdapterLogger, @unchecked Sendable {
    private let lock = NSLock()
    var prefix = "[iWA Demo]"
    var onLine: (@Sendable (String) -> Void)?

    func log(_ event: WalletAdapterLogEvent) {
        let line = WalletAdapterDebugFormatter.format(event, prefix: prefix)
        lock.lock()
        let callback = onLine
        lock.unlock()
        callback?(line)
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
        // Also emit to the device unified log so the line shows in `idevicesyslog`
        // and Console.app even when not attached to Xcode. `%@` (not the raw line)
        // so `%` in payloads is never read as a format specifier.
        NSLog("%@", line)
    }
}
