import Foundation

/// Bitcoin-flavored Base58 encoding used by Solana for pubkeys, signatures,
/// and the wallet-deeplink wire encoding of nonces and ciphertexts.
///
/// Vendored to keep the package zero-dependency. Output matches `bs58` (npm)
/// and `solana_program::bs58`.
public enum Base58 {
    public static let alphabet: [UInt8] = Array(
        "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8
    )

    public static func encode(_ bytes: Data) -> String {
        guard !bytes.isEmpty else { return "" }

        var leadingZeros = 0
        for byte in bytes {
            if byte == 0 { leadingZeros += 1 } else { break }
        }

        var working = [UInt8](bytes)
        var encoded: [UInt8] = []

        var startIndex = leadingZeros
        while startIndex < working.count {
            var carry = 0
            for i in startIndex..<working.count {
                let value = (carry << 8) | Int(working[i])
                working[i] = UInt8(value / 58)
                carry = value % 58
            }
            encoded.append(alphabet[carry])
            while startIndex < working.count && working[startIndex] == 0 {
                startIndex += 1
            }
        }

        for _ in 0..<leadingZeros {
            encoded.append(alphabet[0])
        }

        return String(bytes: encoded.reversed(), encoding: .ascii) ?? ""
    }

    public static func decode(_ string: String) -> Data? {
        guard !string.isEmpty else { return Data() }

        var leadingOnes = 0
        for ch in string {
            if ch == "1" { leadingOnes += 1 } else { break }
        }

        var bytes: [UInt8] = []
        for ch in string {
            guard let asciiValue = ch.asciiValue,
                  let digit = alphabet.firstIndex(of: asciiValue) else {
                return nil
            }
            var carry = digit
            for i in (0..<bytes.count).reversed() {
                let value = Int(bytes[i]) * 58 + carry
                bytes[i] = UInt8(value & 0xff)
                carry = value >> 8
            }
            while carry > 0 {
                bytes.insert(UInt8(carry & 0xff), at: 0)
                carry >>= 8
            }
        }

        var result = [UInt8](repeating: 0, count: leadingOnes)
        result.append(contentsOf: bytes)
        return Data(result)
    }
}
