import Foundation

/// Read packed resources without extraction, links, or executing Electron.
public enum ASARResource {
    public struct Index {
        public let paths: [String]
        public let complete: Bool
        private let data: Data
        private let start: Int
        private let entries: [String: [String: Any]]
        fileprivate init(data: Data, start: Int, entries: [String: [String: Any]], complete: Bool) {
            self.data = data; self.start = start; self.entries = entries; self.complete = complete
            self.paths = entries.keys.sorted()
        }
        public func extract(_ path: String) -> Data? {
            guard let entry = entries[path] else { return nil }
            return ASARResource.read(entry, from: data, start: start)
        }
    }
    private static func header(_ data: Data) -> (root: [String: Any], start: Int)? {
        guard data.count >= 16 else { return nil }
        func uint32(_ offset: Int) -> Int {
            (0..<4).reduce(0) { $0 | (Int(data[offset + $1]) << ($1 * 8)) }
        }
        let headerSize = uint32(4), jsonSize = uint32(12)
        guard uint32(0) == 4, headerSize >= 8, headerSize <= 16_777_216,
              uint32(8) == headerSize - 4, jsonSize > 0, jsonSize <= headerSize - 8,
              headerSize <= data.count - 8,
              let root = try? JSONSerialization.jsonObject(with: data.subdata(in: 16..<16 + jsonSize)) as? [String: Any] else { return nil }
        return (root, headerSize + 8)
    }
    public static func extract(from archive: Data, path: String) -> Data? {
        guard validPath(path), let header = header(archive) else { return nil }
        var entry = header.root
        for part in path.split(separator: "/") {
            guard entry["link"] == nil, entry["unpacked"] as? Bool != true,
                  let files = entry["files"] as? [String: Any], let child = files[String(part)] as? [String: Any] else { return nil }
            entry = child
        }
        return read(entry, from: archive, start: header.start)
    }
    public static func index(from archive: Data, maxEntries: Int = 5_000, maxDepth: Int = 12) throws -> Index {
        guard let header = header(archive) else { throw CocoaError(.fileReadCorruptFile) }
        var entries: [String: [String: Any]] = [:], count = 0
        var complete = true
        func visit(_ entry: [String: Any], path: String, depth: Int) {
            guard depth <= maxDepth, count < maxEntries else { complete = false; return }
            guard entry["link"] == nil, entry["unpacked"] as? Bool != true else { complete = false; return }
            if let files = entry["files"] as? [String: Any] {
                for key in files.keys.sorted() {
                    guard count < maxEntries else { complete = false; break }
                    count += 1
                    guard validPath(key), !key.contains("/"), let child = files[key] as? [String: Any] else { complete = false; continue }
                    visit(child, path: path.isEmpty ? key : path + "/" + key, depth: depth + 1)
                }
            } else if !path.isEmpty { entries[path] = entry }
            else { complete = false }
        }
        visit(header.root, path: "", depth: 0)
        return Index(data: archive, start: header.start, entries: entries, complete: complete)
    }
    public static func validPath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return !path.hasPrefix("/") && !path.contains("\\") && !path.contains("\0") && !parts.isEmpty && parts.count <= 32
            && !parts.contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }
    private static func read(_ entry: [String: Any], from archive: Data, start: Int) -> Data? {
        guard entry["link"] == nil, entry["unpacked"] as? Bool != true,
              let count = entry["size"] as? Int, count > 0, count <= 8_388_608,
              let rawOffset = entry["offset"] as? String, let offset = UInt64(rawOffset),
              offset <= UInt64(archive.count - start), count <= archive.count - start - Int(offset) else { return nil }
        let begin = start + Int(offset)
        let result = archive.subdata(in: begin..<begin + count)
        if let integrity = entry["integrity"] as? [String: Any] {
            guard integrity["algorithm"] as? String == "SHA256", let expected = integrity["hash"] as? String,
                  IconDigest.sha256(result) == expected.lowercased() else { return nil }
        }
        return result
    }
}
