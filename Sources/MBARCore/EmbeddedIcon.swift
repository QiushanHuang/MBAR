import Foundation
import CryptoKit

/// Extract a known, complete upstream image resource without executing code in
/// the owning app. A changed resource fails closed instead of guessing an icon.
public enum EmbeddedIcon {
    public static func extract(from binary: Data, prefix: Data, length: Int, sha256: String) -> Data? {
        guard !prefix.isEmpty, length >= prefix.count, length <= 4_194_304 else { return nil }
        var cursor = binary.startIndex
        while cursor < binary.endIndex,
              let match = binary.range(of: prefix, in: cursor..<binary.endIndex) {
            let start = match.lowerBound
            guard binary.endIndex - start >= length else { return nil }
            let data = binary.subdata(in: start..<start + length)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            if digest == sha256 { return data }
            cursor = start + 1
        }
        return nil
    }
}
