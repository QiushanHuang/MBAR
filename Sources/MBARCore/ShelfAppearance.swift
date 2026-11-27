import Foundation

public enum ShelfMaterial: String, Codable, CaseIterable, Sendable {
    case translucent, frosted, liquid, appleGlass, quietGlass

    public var usesGlassForeground: Bool { self == .appleGlass || self == .quietGlass }
}

public enum ShelfIconTreatment: String, Codable, CaseIterable, Sendable {
    case automatic, system, darkInk, lightInk

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "lightPlate": self = .darkInk
        case "darkPlate": self = .lightInk
        default: self = Self(rawValue: value) ?? .automatic
        }
    }
}

public struct ShelfTint: Codable, Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = Self.channel(red)
        self.green = Self.channel(green)
        self.blue = Self.channel(blue)
    }

    fileprivate static func channel(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }
}

public struct ShelfAppearance: Codable, Equatable, Sendable {
    fileprivate enum CodingKeys: String, CodingKey { case material, tint, intensity, opacity, frostAmount, iconTreatment }
    public static let defaultFrostAmount = 0.35
    public var material: ShelfMaterial
    public var tint: ShelfTint
    public var intensity: Double
    public var opacity: Double
    public var frostAmount: Double
    public var iconTreatment: ShelfIconTreatment

    public init(material: ShelfMaterial, tint: ShelfTint, intensity: Double, opacity: Double = 0.74,
                frostAmount: Double = Self.defaultFrostAmount, iconTreatment: ShelfIconTreatment = .automatic) {
        self.material = material
        self.tint = tint
        self.intensity = ShelfTint.channel(intensity)
        self.opacity = opacity.isFinite ? min(1, max(0.25, opacity)) : 0.74
        self.frostAmount = ShelfTint.channel(frostAmount)
        self.iconTreatment = iconTreatment
    }

    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        let material = try fields.decode(ShelfMaterial.self, forKey: .material)
        self.init(material: material,
                  tint: try fields.decode(ShelfTint.self, forKey: .tint),
                  intensity: try fields.decode(Double.self, forKey: .intensity),
                  opacity: try fields.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.74,
                  frostAmount: try fields.decodeIfPresent(Double.self, forKey: .frostAmount)
                      ?? (material == .appleGlass ? 0 : Self.defaultFrostAmount),
                  iconTreatment: try fields.decodeIfPresent(ShelfIconTreatment.self, forKey: .iconTreatment) ?? .automatic)
    }

    fileprivate var normalized: Self {
        .init(material: material, tint: .init(red: tint.red, green: tint.green, blue: tint.blue),
              intensity: intensity, opacity: opacity, frostAmount: frostAmount, iconTreatment: iconTreatment)
    }
}

public struct ShelfAppearancePreset: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public var appearance: ShelfAppearance
    public var isCustom: Bool { id.hasPrefix("custom.") }

    public static let builtIns: [Self] = [
        .init(id: "frost", name: "原生雾面", appearance: .init(material: .frosted, tint: .init(red: 0.76, green: 0.81, blue: 0.88), intensity: 0)),
        .init(id: "clear", name: "柔光原色", appearance: .init(material: .liquid, tint: .init(red: 0.8, green: 0.92, blue: 1), intensity: 0)),
        .init(id: "apple-glass", name: "桌面水晶", appearance: .init(material: .appleGlass, tint: .init(red: 0.76, green: 0.91, blue: 1), intensity: 0)),
        .init(id: "quiet-glass", name: "静透", appearance: .init(material: .quietGlass, tint: .init(red: 0.20, green: 0.24, blue: 0.31), intensity: 0.11, frostAmount: 0.57, iconTreatment: .lightInk)),
        .init(id: "smoke", name: "烟灰", appearance: .init(material: .translucent, tint: .init(red: 0.20, green: 0.24, blue: 0.31), intensity: 0.72, opacity: 0.84)),
        .init(id: "lagoon", name: "海盐蓝", appearance: .init(material: .liquid, tint: .init(red: 0.16, green: 0.59, blue: 0.86), intensity: 0.65)),
        .init(id: "jade", name: "青玉", appearance: .init(material: .frosted, tint: .init(red: 0.16, green: 0.67, blue: 0.50), intensity: 0.64)),
        .init(id: "apricot", name: "暖杏", appearance: .init(material: .translucent, tint: .init(red: 0.97, green: 0.56, blue: 0.32), intensity: 0.60, opacity: 0.64))
    ]
}

/// A preset and its working variation are separate so changing a slider never overwrites a saved palette.
public struct ShelfAppearancePreferences: Codable, Equatable {
    public private(set) var selectedID: String
    public private(set) var appearance: ShelfAppearance
    public private(set) var customPresets: [ShelfAppearancePreset]
    public var presets: [ShelfAppearancePreset] { ShelfAppearancePreset.builtIns + customPresets }

    public init() {
        let initial = ShelfAppearancePreset.builtIns[0]
        selectedID = initial.id
        appearance = initial.appearance
        customPresets = []
    }

    public init(from decoder: Decoder) throws {
        self.init()
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        var seen = Set<String>()
        for var preset in try fields.decode([ShelfAppearancePreset].self, forKey: .customPresets) {
            guard preset.isCustom, !preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  seen.insert(preset.id).inserted else { continue }
            preset.appearance = preset.appearance.normalized
            customPresets.append(preset)
        }
        if let id = try fields.decodeIfPresent(String.self, forKey: .selectedID),
           let selected = presets.first(where: { $0.id == id }) {
            selectedID = selected.id
            appearance = try fields.decodeIfPresent(ShelfAppearance.self, forKey: .appearance)?.normalized ?? selected.appearance
            // Only the untouched old factory preset follows the new optical tuning.
            // A saved copy, modified variation or explicitly selected 0% stays clear.
            if selected.id == "apple-glass", appearance.frostAmount == 0,
               try !fields.nestedContainer(keyedBy: ShelfAppearance.CodingKeys.self, forKey: .appearance).contains(.frostAmount) {
                var previousFactory = selected.appearance
                previousFactory.frostAmount = 0
                if appearance == previousFactory { appearance = selected.appearance }
            }
        }
    }

    public mutating func select(_ id: String) {
        guard let preset = presets.first(where: { $0.id == id }) else { return }
        selectedID = preset.id
        appearance = preset.appearance
    }

    public mutating func customize(_ value: ShelfAppearance) { appearance = value.normalized }

    public mutating func save(named name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !presets.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else { return false }
        let id = "custom." + UUID().uuidString
        customPresets.append(.init(id: id, name: name, appearance: appearance))
        selectedID = id
        return true
    }

    public mutating func update(_ id: String) {
        guard selectedID == id, let index = customPresets.firstIndex(where: { $0.id == id }) else { return }
        customPresets[index].appearance = appearance
    }

    public mutating func delete(_ id: String) {
        guard let index = customPresets.firstIndex(where: { $0.id == id }) else { return }
        customPresets.remove(at: index)
        if selectedID == id { select(ShelfAppearancePreset.builtIns[0].id) }
    }
}
