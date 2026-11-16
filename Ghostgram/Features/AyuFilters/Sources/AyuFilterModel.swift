import Foundation

public struct AyuFilterRule: Codable, Equatable, Identifiable {
    public var id: Int64
    public var dialogId: Int64?
    public var text: String
    public var reversed: Bool
    public var caseInsensitive: Bool
    public var enabled: Bool
    public var autoClickButton: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case dialogId
        case text
        case reversed
        case caseInsensitive
        case enabled
        case autoClickButton
    }

    public init(
        id: Int64,
        dialogId: Int64? = nil,
        text: String,
        reversed: Bool = false,
        caseInsensitive: Bool = true,
        enabled: Bool = true,
        autoClickButton: Bool? = nil
    ) {
        self.id = id
        self.dialogId = (dialogId == 0) ? nil : dialogId
        self.text = text
        self.reversed = reversed
        self.caseInsensitive = caseInsensitive
        self.enabled = enabled
        self.autoClickButton = autoClickButton
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let idInt = try? container.decode(Int64.self, forKey: .id) {
            self.id = idInt
        } else if let idString = try? container.decode(String.self, forKey: .id), let idInt = Int64(idString) {
            self.id = idInt
        } else {
            self.id = Int64(Date().timeIntervalSince1970 * 1000)
        }

        if let dId = try? container.decode(Int64.self, forKey: .dialogId) {
            self.dialogId = (dId == 0) ? nil : dId
        } else if let dString = try? container.decode(String.self, forKey: .dialogId), let dId = Int64(dString) {
            self.dialogId = (dId == 0) ? nil : dId
        } else {
            self.dialogId = nil
        }

        self.text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        self.reversed = try container.decodeIfPresent(Bool.self, forKey: .reversed) ?? false
        self.caseInsensitive = try container.decodeIfPresent(Bool.self, forKey: .caseInsensitive) ?? true
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.autoClickButton = try container.decodeIfPresent(Bool.self, forKey: .autoClickButton)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.dialogId ?? 0, forKey: .dialogId)
        try container.encode(self.text, forKey: .text)
        try container.encode(self.reversed, forKey: .reversed)
        try container.encode(self.caseInsensitive, forKey: .caseInsensitive)
        try container.encode(self.enabled, forKey: .enabled)
        try container.encodeIfPresent(self.autoClickButton, forKey: .autoClickButton)
    }
}

public struct AyuFiltersConfig: Codable, Equatable {
    public var version: Int
    public var isEnabled: Bool
    public var autoClickButtonsEnabled: Bool
    public var filters: [AyuFilterRule]
    public var exclusions: [Int64]

    enum CodingKeys: String, CodingKey {
        case version
        case isEnabled
        case autoClickButtonsEnabled
        case filters
        case exclusions
    }

    public init(
        version: Int = 2,
        isEnabled: Bool = true,
        autoClickButtonsEnabled: Bool = false,
        filters: [AyuFilterRule] = [],
        exclusions: [Int64] = []
    ) {
        self.version = version
        self.isEnabled = isEnabled
        self.autoClickButtonsEnabled = autoClickButtonsEnabled
        self.filters = filters
        self.exclusions = exclusions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 2
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.autoClickButtonsEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoClickButtonsEnabled) ?? false
        self.filters = try container.decodeIfPresent([AyuFilterRule].self, forKey: .filters) ?? []

        // Flexible exclusions decoding: array of Int64 or array of objects with dialogId
        if let directIds = try? container.decode([Int64].self, forKey: .exclusions) {
            self.exclusions = directIds
        } else if let stringIds = try? container.decode([String].self, forKey: .exclusions) {
            self.exclusions = stringIds.compactMap { Int64($0) }
        } else if let objectArray = try? container.decode([[String: Int64]].self, forKey: .exclusions) {
            self.exclusions = objectArray.compactMap { $0["dialogId"] }
        } else {
            self.exclusions = []
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.version, forKey: .version)
        try container.encode(self.isEnabled, forKey: .isEnabled)
        try container.encode(self.autoClickButtonsEnabled, forKey: .autoClickButtonsEnabled)
        try container.encode(self.filters, forKey: .filters)
        try container.encode(self.exclusions, forKey: .exclusions)
    }
}
