import Foundation
import CryptoKit

/// Read a named packed resource, without extracting files or executing Electron.
public enum ASARResource {
    public static func extract(from archive: Data, path: String) -> Data? {
        guard archive.count >= 16, !path.hasPrefix("/") else { return nil }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 32,
              !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { return nil }
        func uint32(_ offset: Int) -> Int {
            (0..<4).reduce(0) { $0 | (Int(archive[offset + $1]) << ($1 * 8)) }
        }
        let headerSize = uint32(4), jsonSize = uint32(12)
        guard uint32(0) == 4, headerSize >= 8, headerSize <= 16_777_216,
              uint32(8) == headerSize - 4, jsonSize > 0, jsonSize <= headerSize - 8,
              headerSize <= archive.count - 8,
              let root = try? JSONSerialization.jsonObject(with: archive.subdata(in: 16..<16 + jsonSize)) as? [String: Any] else { return nil }
        var entry = root
        for part in parts {
            guard let files = entry["files"] as? [String: Any], let child = files[String(part)] as? [String: Any] else { return nil }
            entry = child
        }
        guard entry["link"] == nil, entry["unpacked"] as? Bool != true,
              let count = entry["size"] as? Int, count > 0, count <= 8_388_608,
              let rawOffset = entry["offset"] as? String, let offset = UInt64(rawOffset) else { return nil }
        let contentStart = headerSize + 8
        guard offset <= UInt64(archive.count - contentStart),
              count <= archive.count - contentStart - Int(offset) else { return nil }
        let start = contentStart + Int(offset)
        let result = archive.subdata(in: start..<start + count)
        if let integrity = entry["integrity"] as? [String: Any] {
            guard integrity["algorithm"] as? String == "SHA256", let expected = integrity["hash"] as? String else { return nil }
            let actual = SHA256.hash(data: result).map { String(format: "%02x", $0) }.joined()
            guard actual == expected.lowercased() else { return nil }
        }
        return result
    }
}
