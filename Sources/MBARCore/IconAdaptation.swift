import Foundation
import CryptoKit

public enum IconDisplayMode: String, Codable, CaseIterable, Sendable { case original, template }
public enum IconOrigin: String, Codable, Sendable { case automatic, userSelected, custom, nativeSnapshot }
public enum IconLocator: Codable, Equatable, Hashable, Sendable {
    case file(String)
    case asar(archive: String, entry: String)
    case imported(String)
    case catalog(String)
    public var label: String {
        switch self {
        case .file(let path), .imported(let path): return path
        case .asar(let archive, let entry): return "\(archive) → \(entry)"
        case .catalog(let name): return "Assets.car → \(name)"
        }
    }
    public var resourcePath: String {
        switch self {
        case .file(let path), .imported(let path): return path
        case .asar(let archive, _): return archive
        case .catalog: return "Assets.car"
        }
    }
}
public struct IconAppIdentity: Codable, Equatable, Sendable {
    public var bundleID: String
    public var path: String
    public var version: String
    public var shortVersion: String
    public init(bundleID: String, path: String, version: String, shortVersion: String) {
        self.bundleID = bundleID; self.path = path; self.version = version; self.shortVersion = shortVersion
    }
    public var key: String { bundleID + "|" + path }
}
public enum IconValidation { case valid, needsConfirmation, differentInstallation }
public struct IconMapping: Codable, Equatable, Sendable {
    public var identity: IconAppIdentity
    public var locator: IconLocator
    public var digest: String
    public var mode: IconDisplayMode
    public var origin: IconOrigin
    public var selectedAt: Date
    public var sourceRevision: String?
    public init(identity: IconAppIdentity, locator: IconLocator, digest: String, mode: IconDisplayMode, origin: IconOrigin, selectedAt: Date = Date(), sourceRevision: String? = nil) {
        self.identity = identity; self.locator = locator; self.digest = digest
        self.mode = mode; self.origin = origin; self.selectedAt = selectedAt
        self.sourceRevision = sourceRevision
    }
    public func validation(current: IconAppIdentity, digest: String?) -> IconValidation {
        guard identity.key == current.key else { return .differentInstallation }
        if origin == .nativeSnapshot && (identity.version != current.version || identity.shortVersion != current.shortVersion) { return .needsConfirmation }
        return digest == self.digest ? .valid : .needsConfirmation
    }
}
public struct IconEvidence: Sendable {
    public let path: String
    public let digest: String
    public let transparent: Bool
    public let menuSized: Bool
    public let family: String?
    public let declaredTemplate: Bool
    public init(path: String, digest: String, transparent: Bool, menuSized: Bool, family: String? = nil, declaredTemplate: Bool = false) {
        self.path = path; self.digest = digest; self.transparent = transparent; self.menuSized = menuSized; self.family = family
        self.declaredTemplate = declaredTemplate
    }
    public static func tokens(_ text: String) -> [String] {
        let camel = text.replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "([A-Z])([A-Z][a-z])", with: "$1 $2", options: .regularExpression)
        return camel.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }
    private var name: String { URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent }
    private var nameTokens: [String] { Self.tokens(name) }
    public var strongName: Bool {
        let t = nameTokens
        return t.contains("tray") || t.contains(where: { $0.hasPrefix("menubar") || $0.hasPrefix("statusbar") || $0.hasPrefix("statusicon") || $0.hasPrefix("trayicon") })
            || zip(t, t.dropFirst()).contains { ($0 == "status" && ["item", "bar", "icon"].contains($1)) || ($0 == "menu" && $1 == "bar") }
    }
    public var template: Bool { declaredTemplate || nameTokens.contains("template") }
    public var excluded: Bool {
        let t = Self.tokens(path)
        return !Set(t).isDisjoint(with: ["appicon", "favicon", "installer", "dock", "toolbar"])
            || zip(t, t.dropFirst()).contains { ($0 == "app" && $1 == "icon") || ($0 == "tool" && $1 == "bar") }
    }
    public var ambiguousVariant: Bool {
        let stem = name.replacingOccurrences(of: "@[123]x$", with: "", options: .regularExpression)
        let t = Self.tokens(stem)
        let context = Self.tokens((path as NSString).deletingLastPathComponent) + t
        return !Set(context).isDisjoint(with: ["error", "disabled", "enabled", "connected", "disconnected", "offline", "online", "active", "inactive", "dark", "light", "black", "white", "pressed", "selected", "highlighted", "click", "remind", "debug", "expired", "loading"])
            || t.contains { $0.contains(where: \.isNumber) }
    }
    public var score: Int {
        let directory = Self.tokens((path as NSString).deletingLastPathComponent)
        return (strongName ? 50 : (nameTokens.contains("status") || nameTokens.contains("icon") ? 10 : 0))
            + (directory.contains("tray") || directory.contains("menubar") ? 20 : 0)
            + (template ? 15 : 0) + (transparent ? 10 : 0) + (menuSized ? 5 : 0)
    }
    public var worthInspecting: Bool {
        !excluded && (strongName || template || !Set(Self.tokens(path)).isDisjoint(with: ["status", "icon", "icons", "tray", "menubar"]))
    }
}
public enum IconRanker {
    public static func automaticIndex(_ entries: [IconEvidence], complete: Bool, itemCount: Int) -> Int? {
        guard complete, itemCount == 1 else { return nil }
        let ranked = entries.indices.filter { !entries[$0].excluded }.sorted {
            entries[$0].score == entries[$1].score ? entries[$0].path < entries[$1].path : entries[$0].score > entries[$1].score
        }
        guard let first = ranked.first else { return nil }
        let winner = entries[first]
        guard winner.strongName, winner.menuSized, winner.score >= 80, !winner.ambiguousVariant else { return nil }
        // Duplicates cannot hide a competing state variant from the decision.
        guard !ranked.contains(where: { entries[$0].ambiguousVariant && (entries[$0].strongName || winner.score - entries[$0].score < 25) }) else { return nil }
        let competitor = ranked.dropFirst().first {
            entries[$0].digest != winner.digest && (winner.family == nil || entries[$0].family != winner.family)
        }
        guard competitor.map({ winner.score - entries[$0].score >= 25 }) ?? true else { return nil }
        return first
    }
}
public struct IconRequestGate {
    private var generations: [String: Int] = [:]
    public init() {}
    public mutating func begin(_ key: String) -> Int {
        generations[key, default: 0] += 1; return generations[key]!
    }
    public mutating func invalidate(_ key: String) { _ = begin(key) }
    public func accepts(_ key: String, token: Int) -> Bool { generations[key] == token }
}
public enum IconDigest {
    public static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}

/// Call from one executor. All mutations persist atomically before becoming visible.
public final class IconMappingStore {
    private struct Document: Codable {
        var schemaVersion = 1
        var mappings: [String: IconMapping] = [:]
        var undo: [String: UndoRecord] = [:]
    }
    private struct UndoRecord: Codable { var mapping: IconMapping? }
    public let directory: URL
    private var document: Document
    public init(directory: URL) throws {
        self.directory = directory
        let url = directory.appendingPathComponent("IconMappings.json")
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            guard data.count <= 8_388_608 else { throw CocoaError(.fileReadTooLarge) }
            document = try JSONDecoder().decode(Document.self, from: data)
            guard document.schemaVersion == 1 else { throw CocoaError(.fileReadCorruptFile) }
        } else { document = Document() }
    }
    public func mapping(for key: String) -> IconMapping? { document.mappings[key] }
    public func canUndo(for key: String) -> Bool { document.undo[key] != nil }
    public func set(_ mapping: IconMapping?, for key: String, userInitiated: Bool = true) throws {
        var next = document
        if userInitiated { next.undo[key] = UndoRecord(mapping: next.mappings[key]) }
        next.mappings[key] = mapping
        try persist(next)
    }
    public func undo(for key: String) throws {
        guard let previous = document.undo[key] else { return }
        var next = document
        next.mappings[key] = previous.mapping; next.undo.removeValue(forKey: key)
        try persist(next)
    }
    private func persist(_ next: Document) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(next).write(to: directory.appendingPathComponent("IconMappings.json"), options: .atomic)
        document = next
    }
}
