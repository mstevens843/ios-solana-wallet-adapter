import Foundation

// Minimal TweetNaCl-compatible XSalsa20-Poly1305 routines.
// Based on TweetNaCl.js / nacl-fast.js by Dmitry Chestnykh and Devi Mandiri.
// Public domain. See https://tweetnacl.js.org/.
enum TweetNaCl {
    private static let sigma = Array("expand 32-byte k".utf8)

    static func boxBeforeNM(sharedSecret: Data) -> Data {
        Data(hsalsa20(nonce16: [UInt8](repeating: 0, count: 16), key: Array(sharedSecret)))
    }

    static func secretBoxSeal(message: Data, nonce: Data, key: Data) -> Data {
        let stream = xsalsa20Stream(length: 32 + message.count, nonce: Array(nonce), key: Array(key))
        let encrypted = zip(Array(message), stream.dropFirst(32)).map { $0 ^ $1 }
        let tag = poly1305Mac(message: encrypted, key: Array(stream.prefix(32)))
        return Data(tag + encrypted)
    }

    static func secretBoxOpen(box: Data, nonce: Data, key: Data) -> Data? {
        guard box.count >= 16 else { return nil }
        let bytes = Array(box)
        let tag = Array(bytes.prefix(16))
        let encrypted = Array(bytes.dropFirst(16))
        let stream = xsalsa20Stream(length: 32 + encrypted.count, nonce: Array(nonce), key: Array(key))
        let expectedTag = poly1305Mac(message: encrypted, key: Array(stream.prefix(32)))
        guard constantTimeEqual(tag, expectedTag) else { return nil }
        return Data(zip(encrypted, stream.dropFirst(32)).map { $0 ^ $1 })
    }

    private static func xsalsa20Stream(length: Int, nonce: [UInt8], key: [UInt8]) -> [UInt8] {
        let subkey = hsalsa20(nonce16: Array(nonce[0..<16]), key: key)
        let subnonce = Array(nonce[16..<24])
        return salsa20Stream(length: length, nonce8: subnonce, key: subkey)
    }

    private static func hsalsa20(nonce16: [UInt8], key: [UInt8]) -> [UInt8] {
        var x = salsaState(nonce: nonce16, key: key, counter: nil)
        for _ in 0..<10 {
            quarterRound(&x, 0, 4, 8, 12)
            quarterRound(&x, 5, 9, 13, 1)
            quarterRound(&x, 10, 14, 2, 6)
            quarterRound(&x, 15, 3, 7, 11)
            quarterRound(&x, 0, 1, 2, 3)
            quarterRound(&x, 5, 6, 7, 4)
            quarterRound(&x, 10, 11, 8, 9)
            quarterRound(&x, 15, 12, 13, 14)
        }
        return wordsToBytes([x[0], x[5], x[10], x[15], x[6], x[7], x[8], x[9]])
    }

    private static func salsa20Stream(length: Int, nonce8: [UInt8], key: [UInt8]) -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity(length)
        var counter: UInt64 = 0
        while output.count < length {
            let block = salsa20Block(nonce8: nonce8, key: key, counter: counter)
            output.append(contentsOf: block.prefix(length - output.count))
            counter &+= 1
        }
        return output
    }

    private static func salsa20Block(nonce8: [UInt8], key: [UInt8], counter: UInt64) -> [UInt8] {
        let original = salsaState(nonce: nonce8, key: key, counter: counter)
        var x = original
        for _ in 0..<10 {
            quarterRound(&x, 0, 4, 8, 12)
            quarterRound(&x, 5, 9, 13, 1)
            quarterRound(&x, 10, 14, 2, 6)
            quarterRound(&x, 15, 3, 7, 11)
            quarterRound(&x, 0, 1, 2, 3)
            quarterRound(&x, 5, 6, 7, 4)
            quarterRound(&x, 10, 11, 8, 9)
            quarterRound(&x, 15, 12, 13, 14)
        }
        for i in 0..<16 {
            x[i] = x[i] &+ original[i]
        }
        return wordsToBytes(x)
    }

    private static func salsaState(nonce: [UInt8], key: [UInt8], counter: UInt64?) -> [UInt32] {
        var state = [UInt32](repeating: 0, count: 16)
        state[0] = load32(sigma, 0)
        state[5] = load32(sigma, 4)
        state[10] = load32(sigma, 8)
        state[15] = load32(sigma, 12)
        state[1] = load32(key, 0)
        state[2] = load32(key, 4)
        state[3] = load32(key, 8)
        state[4] = load32(key, 12)
        state[11] = load32(key, 16)
        state[12] = load32(key, 20)
        state[13] = load32(key, 24)
        state[14] = load32(key, 28)
        state[6] = load32(nonce, 0)
        state[7] = load32(nonce, 4)
        if let counter {
            state[8] = UInt32(truncatingIfNeeded: counter)
            state[9] = UInt32(truncatingIfNeeded: counter >> 32)
        } else {
            state[8] = load32(nonce, 8)
            state[9] = load32(nonce, 12)
        }
        return state
    }

    private static func quarterRound(_ x: inout [UInt32], _ a: Int, _ b: Int, _ c: Int, _ d: Int) {
        x[b] ^= rotateLeft(x[a] &+ x[d], 7)
        x[c] ^= rotateLeft(x[b] &+ x[a], 9)
        x[d] ^= rotateLeft(x[c] &+ x[b], 13)
        x[a] ^= rotateLeft(x[d] &+ x[c], 18)
    }

    private static func rotateLeft(_ value: UInt32, _ count: UInt32) -> UInt32 {
        (value << count) | (value >> (32 - count))
    }

    private static func load32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) |
            (UInt32(bytes[offset + 1]) << 8) |
            (UInt32(bytes[offset + 2]) << 16) |
            (UInt32(bytes[offset + 3]) << 24)
    }

    private static func wordsToBytes(_ words: [UInt32]) -> [UInt8] {
        words.flatMap { word in
            [
                UInt8(truncatingIfNeeded: word),
                UInt8(truncatingIfNeeded: word >> 8),
                UInt8(truncatingIfNeeded: word >> 16),
                UInt8(truncatingIfNeeded: word >> 24),
            ]
        }
    }

    private static func constantTimeEqual(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<lhs.count {
            diff |= lhs[i] ^ rhs[i]
        }
        return diff == 0
    }

    private static func poly1305Mac(message: [UInt8], key: [UInt8]) -> [UInt8] {
        var poly = Poly1305(key: key)
        poly.update(message)
        return poly.finish()
    }

    private struct Poly1305 {
        var r = [Int64](repeating: 0, count: 10)
        var h = [Int64](repeating: 0, count: 10)
        var pad = [Int64](repeating: 0, count: 8)
        var buffer = [UInt8](repeating: 0, count: 16)
        var leftover = 0
        var fin = false

        init(key: [UInt8]) {
            let t0 = Int64(key[0]) | (Int64(key[1]) << 8)
            let t1 = Int64(key[2]) | (Int64(key[3]) << 8)
            let t2 = Int64(key[4]) | (Int64(key[5]) << 8)
            let t3 = Int64(key[6]) | (Int64(key[7]) << 8)
            let t4 = Int64(key[8]) | (Int64(key[9]) << 8)
            let t5 = Int64(key[10]) | (Int64(key[11]) << 8)
            let t6 = Int64(key[12]) | (Int64(key[13]) << 8)
            let t7 = Int64(key[14]) | (Int64(key[15]) << 8)
            r[0] = t0 & 0x1fff
            r[1] = ((t0 >> 13) | (t1 << 3)) & 0x1fff
            r[2] = ((t1 >> 10) | (t2 << 6)) & 0x1f03
            r[3] = ((t2 >> 7) | (t3 << 9)) & 0x1fff
            r[4] = ((t3 >> 4) | (t4 << 12)) & 0x00ff
            r[5] = (t4 >> 1) & 0x1ffe
            r[6] = ((t4 >> 14) | (t5 << 2)) & 0x1fff
            r[7] = ((t5 >> 11) | (t6 << 5)) & 0x1f81
            r[8] = ((t6 >> 8) | (t7 << 8)) & 0x1fff
            r[9] = (t7 >> 5) & 0x007f
            for i in 0..<8 {
                pad[i] = Int64(key[16 + i * 2]) | (Int64(key[17 + i * 2]) << 8)
            }
        }

        mutating func update(_ message: [UInt8]) {
            var mpos = 0
            var bytes = message.count
            if leftover != 0 {
                let want = min(16 - leftover, bytes)
                for i in 0..<want {
                    buffer[leftover + i] = message[mpos + i]
                }
                bytes -= want
                mpos += want
                leftover += want
                if leftover < 16 { return }
                blocks(buffer, 0, 16)
                leftover = 0
            }
            if bytes >= 16 {
                let want = bytes - (bytes % 16)
                blocks(message, mpos, want)
                mpos += want
                bytes -= want
            }
            if bytes != 0 {
                for i in 0..<bytes {
                    buffer[leftover + i] = message[mpos + i]
                }
                leftover += bytes
            }
        }

        mutating func finish() -> [UInt8] {
            if leftover != 0 {
                var i = leftover
                buffer[i] = 1
                i += 1
                while i < 16 {
                    buffer[i] = 0
                    i += 1
                }
                fin = true
                blocks(buffer, 0, 16)
            }

            var c = h[1] >> 13
            h[1] &= 0x1fff
            for i in 2..<10 {
                h[i] += c
                c = h[i] >> 13
                h[i] &= 0x1fff
            }
            h[0] += c * 5
            c = h[0] >> 13
            h[0] &= 0x1fff
            h[1] += c
            c = h[1] >> 13
            h[1] &= 0x1fff
            h[2] += c

            var g = [Int64](repeating: 0, count: 10)
            g[0] = h[0] + 5
            c = g[0] >> 13
            g[0] &= 0x1fff
            for i in 1..<10 {
                g[i] = h[i] + c
                c = g[i] >> 13
                g[i] &= 0x1fff
            }
            g[9] -= 1 << 13
            if c != 0 { h = g }

            h[0] = (h[0] | (h[1] << 13)) & 0xffff
            h[1] = ((h[1] >> 3) | (h[2] << 10)) & 0xffff
            h[2] = ((h[2] >> 6) | (h[3] << 7)) & 0xffff
            h[3] = ((h[3] >> 9) | (h[4] << 4)) & 0xffff
            h[4] = ((h[4] >> 12) | (h[5] << 1) | (h[6] << 14)) & 0xffff
            h[5] = ((h[6] >> 2) | (h[7] << 11)) & 0xffff
            h[6] = ((h[7] >> 5) | (h[8] << 8)) & 0xffff
            h[7] = ((h[8] >> 8) | (h[9] << 5)) & 0xffff

            var f = h[0] + pad[0]
            h[0] = f & 0xffff
            for i in 1..<8 {
                f = h[i] + pad[i] + (f >> 16)
                h[i] = f & 0xffff
            }

            var mac = [UInt8](repeating: 0, count: 16)
            for i in 0..<8 {
                mac[i * 2] = UInt8(truncatingIfNeeded: h[i])
                mac[i * 2 + 1] = UInt8(truncatingIfNeeded: h[i] >> 8)
            }
            return mac
        }

        mutating func blocks(_ message: [UInt8], _ offset: Int, _ byteCount: Int) {
            let hibit: Int64 = fin ? 0 : (1 << 11)
            var mpos = offset
            var bytes = byteCount

            while bytes >= 16 {
                let t0 = Int64(message[mpos]) | (Int64(message[mpos + 1]) << 8)
                h[0] += t0 & 0x1fff
                let t1 = Int64(message[mpos + 2]) | (Int64(message[mpos + 3]) << 8)
                h[1] += ((t0 >> 13) | (t1 << 3)) & 0x1fff
                let t2 = Int64(message[mpos + 4]) | (Int64(message[mpos + 5]) << 8)
                h[2] += ((t1 >> 10) | (t2 << 6)) & 0x1fff
                let t3 = Int64(message[mpos + 6]) | (Int64(message[mpos + 7]) << 8)
                h[3] += ((t2 >> 7) | (t3 << 9)) & 0x1fff
                let t4 = Int64(message[mpos + 8]) | (Int64(message[mpos + 9]) << 8)
                h[4] += ((t3 >> 4) | (t4 << 12)) & 0x1fff
                h[5] += (t4 >> 1) & 0x1fff
                let t5 = Int64(message[mpos + 10]) | (Int64(message[mpos + 11]) << 8)
                h[6] += ((t4 >> 14) | (t5 << 2)) & 0x1fff
                let t6 = Int64(message[mpos + 12]) | (Int64(message[mpos + 13]) << 8)
                h[7] += ((t5 >> 11) | (t6 << 5)) & 0x1fff
                let t7 = Int64(message[mpos + 14]) | (Int64(message[mpos + 15]) << 8)
                h[8] += ((t6 >> 8) | (t7 << 8)) & 0x1fff
                h[9] += (t7 >> 5) | hibit

                var d = [Int64](repeating: 0, count: 10)
                for i in 0..<10 {
                    var sum: Int64 = 0
                    for j in 0...i {
                        sum += h[j] * r[i - j]
                    }
                    if i + 1 < 10 {
                        for j in (i + 1)..<10 {
                            sum += h[j] * (5 * r[i + 10 - j])
                        }
                    }
                    d[i] = sum
                }

                var carry: Int64 = 0
                for i in 0..<10 {
                    d[i] += carry
                    carry = d[i] >> 13
                    d[i] &= 0x1fff
                }
                d[0] += carry * 5
                carry = d[0] >> 13
                d[0] &= 0x1fff
                d[1] += carry
                h = d

                mpos += 16
                bytes -= 16
            }
        }
    }
}
