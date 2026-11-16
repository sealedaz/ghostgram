import Foundation

public enum AyuFilterMatchMode: String {
    case regex
    case contains
    case exact
    case startsWith = "startswith"
    case endsWith = "endswith"
    case word
}

public struct AyuFilterMatchResult {
    public let matchedRule: AyuFilterRule
    public let shouldAutoClickButton: Bool
    public let targetButtonPattern: String?
}

public final class AyuCompiledFilter {
    public let rule: AyuFilterRule
    public let matchMode: AyuFilterMatchMode
    public let cleanPattern: String
    public let buttonPattern: String?
    public let regex: NSRegularExpression?
    public let buttonRegex: NSRegularExpression?

    public init(rule: AyuFilterRule) {
        self.rule = rule

        var text = rule.text
        var mode: AyuFilterMatchMode = .regex

        // 1. Parse <type>CONST</type> tag
        let typePattern = "<type>([a-zA-Z]+)</type>"
        if let typeRegex = try? NSRegularExpression(pattern: typePattern, options: .caseInsensitive) {
            let nsString = text as NSString
            if let match = typeRegex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsString.length)) {
                let typeString = nsString.substring(with: match.range(at: 1)).lowercased()
                if let parsedMode = AyuFilterMatchMode(rawValue: typeString) {
                    mode = parsedMode
                }
                text = typeRegex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: nsString.length), withTemplate: "")
            }
        }
        self.matchMode = mode

        // 2. Parse <button>...</button> or <button> tag
        var buttonPat: String? = nil
        let buttonTagPattern = "<button>(.*?)</button>|<button>"
        if let btnRegex = try? NSRegularExpression(pattern: buttonTagPattern, options: .caseInsensitive) {
            let nsString = text as NSString
            if let match = btnRegex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsString.length)) {
                if match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound {
                    buttonPat = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    buttonPat = ""
                }
                text = btnRegex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: nsString.length), withTemplate: "")
            }
        }
        self.buttonPattern = buttonPat

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.cleanPattern = trimmedText

        // 3. Compile NSRegularExpression safely with error protection
        var compiledRegex: NSRegularExpression? = nil
        if mode == .regex && !trimmedText.isEmpty {
            var options: NSRegularExpression.Options = [.dotMatchesLineSeparators]
            if rule.caseInsensitive {
                options.insert(.caseInsensitive)
            }
            compiledRegex = try? NSRegularExpression(pattern: trimmedText, options: options)
        } else if mode == .word && !trimmedText.isEmpty {
            let wordPattern = "\\b\(NSRegularExpression.escapedPattern(for: trimmedText))\\b"
            var options: NSRegularExpression.Options = []
            if rule.caseInsensitive {
                options.insert(.caseInsensitive)
            }
            compiledRegex = try? NSRegularExpression(pattern: wordPattern, options: options)
        }
        self.regex = compiledRegex

        // 4. Compile button regex if button pattern is non-empty
        var compiledButtonRegex: NSRegularExpression? = nil
        if let bPat = buttonPat, !bPat.isEmpty {
            var options: NSRegularExpression.Options = [.dotMatchesLineSeparators]
            if rule.caseInsensitive {
                options.insert(.caseInsensitive)
            }
            compiledButtonRegex = try? NSRegularExpression(pattern: bPat, options: options)
        }
        self.buttonRegex = compiledButtonRegex
    }

    public func matches(text: String, buttonTitles: [String]) -> Bool {
        guard self.rule.enabled else {
            return false
        }

        // If <button> tag is specified, verify button matching first
        if let bPat = self.buttonPattern {
            if buttonTitles.isEmpty {
                return self.rule.reversed
            }
            if !bPat.isEmpty {
                var buttonMatched = false
                for title in buttonTitles {
                    if let bRegex = self.buttonRegex {
                        let range = NSRange(location: 0, length: (title as NSString).length)
                        if bRegex.firstMatch(in: title, options: [], range: range) != nil {
                            buttonMatched = true
                            break
                        }
                    } else {
                        let compareOptions: String.CompareOptions = self.rule.caseInsensitive ? [.caseInsensitive] : []
                        if title.range(of: bPat, options: compareOptions) != nil {
                            buttonMatched = true
                            break
                        }
                    }
                }
                if !buttonMatched {
                    return self.rule.reversed
                }
            }
        }

        // If cleanPattern is empty (e.g. filter had only <button>), matching button is sufficient
        if self.cleanPattern.isEmpty {
            let matched = (self.buttonPattern != nil)
            return self.rule.reversed ? !matched : matched
        }

        var matched = false
        switch self.matchMode {
        case .regex, .word:
            if let regex = self.regex {
                let range = NSRange(location: 0, length: (text as NSString).length)
                matched = regex.firstMatch(in: text, options: [], range: range) != nil
            }
        case .contains:
            let options: String.CompareOptions = self.rule.caseInsensitive ? [.caseInsensitive] : []
            matched = text.range(of: self.cleanPattern, options: options) != nil
        case .exact:
            if self.rule.caseInsensitive {
                matched = text.caseInsensitiveCompare(self.cleanPattern) == .orderedSame
            } else {
                matched = (text == self.cleanPattern)
            }
        case .startsWith:
            if self.rule.caseInsensitive {
                matched = text.lowercased().hasPrefix(self.cleanPattern.lowercased())
            } else {
                matched = text.hasPrefix(self.cleanPattern)
            }
        case .endsWith:
            if self.rule.caseInsensitive {
                matched = text.lowercased().hasSuffix(self.cleanPattern.lowercased())
            } else {
                matched = text.hasSuffix(self.cleanPattern)
            }
        }

        return self.rule.reversed ? !matched : matched
    }
}

public final class AyuFiltersEngine {
    private var sharedFilters: [AyuCompiledFilter] = []
    private var perChatFilters: [Int64: [AyuCompiledFilter]] = [:]
    private var exclusions: Set<Int64> = []
    private var isEnabled: Bool = true
    private var autoClickButtonsEnabled: Bool = false
    private let lock = NSLock()

    public init() {}

    public func compile(config: AyuFiltersConfig) {
        self.lock.lock()
        defer { self.lock.unlock() }

        self.isEnabled = config.isEnabled
        self.autoClickButtonsEnabled = config.autoClickButtonsEnabled
        self.exclusions = Set(config.exclusions)

        var newShared: [AyuCompiledFilter] = []
        var newPerChat: [Int64: [AyuCompiledFilter]] = [:]

        for rule in config.filters where rule.enabled {
            let compiled = AyuCompiledFilter(rule: rule)
            if let dialogId = rule.dialogId, dialogId != 0 {
                newPerChat[dialogId, default: []].append(compiled)
            } else {
                newShared.append(compiled)
            }
        }

        self.sharedFilters = newShared
        self.perChatFilters = newPerChat
    }

    public func shouldFilter(dialogId: Int64, text: String, buttonTitles: [String]) -> AyuFilterMatchResult? {
        self.lock.lock()
        defer { self.lock.unlock() }

        guard self.isEnabled else {
            return nil
        }

        // Exclusions: if the chat is in exclusions, skip filtering completely
        if self.exclusions.contains(dialogId) {
            return nil
        }

        // 1. Check Per-chat filters first
        if let chatFilters = self.perChatFilters[dialogId] {
            for filter in chatFilters {
                if filter.matches(text: text, buttonTitles: buttonTitles) {
                    let shouldClick = (self.autoClickButtonsEnabled && (filter.rule.autoClickButton ?? true))
                    return AyuFilterMatchResult(
                        matchedRule: filter.rule,
                        shouldAutoClickButton: shouldClick,
                        targetButtonPattern: filter.buttonPattern
                    )
                }
            }
        }

        // 2. Check Shared (global) filters
        for filter in self.sharedFilters {
            if filter.matches(text: text, buttonTitles: buttonTitles) {
                let shouldClick = (self.autoClickButtonsEnabled && (filter.rule.autoClickButton ?? true))
                return AyuFilterMatchResult(
                    matchedRule: filter.rule,
                    shouldAutoClickButton: shouldClick,
                    targetButtonPattern: filter.buttonPattern
                )
            }
        }

        return nil
    }
}
