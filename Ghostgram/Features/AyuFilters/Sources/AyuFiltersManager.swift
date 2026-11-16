import Foundation
import UIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext
import GGCore

public final class AyuFiltersManager {
    public static let shared = AyuFiltersManager()

    private let engine = AyuFiltersEngine()
    private let storage = AyuFiltersStorage.shared
    private(set) public var config: AyuFiltersConfig
    private var clickedMessageIds = Set<MessageId>()
    private var lastClickTime: TimeInterval = 0.0
    private let lock = NSLock()

    private init() {
        let loaded = self.storage.load()
        self.config = loaded
        self.engine.compile(config: loaded)
    }

    public func reload() {
        self.lock.lock()
        let loaded = self.storage.load()
        self.config = loaded
        self.engine.compile(config: loaded)
        self.lock.unlock()
    }

    public func setEnabled(_ enabled: Bool) {
        self.lock.lock()
        self.config.isEnabled = enabled
        self.storage.save(self.config)
        self.engine.compile(config: self.config)
        self.lock.unlock()
    }

    public func setAutoClickButtonsEnabled(_ enabled: Bool) {
        self.lock.lock()
        self.config.autoClickButtonsEnabled = enabled
        self.storage.save(self.config)
        self.engine.compile(config: self.config)
        self.lock.unlock()
    }

    public func addRule(_ rule: AyuFilterRule) {
        self.lock.lock()
        self.config.filters.removeAll { $0.id == rule.id }
        self.config.filters.insert(rule, at: 0)
        self.storage.save(self.config)
        self.engine.compile(config: self.config)
        self.lock.unlock()
    }

    public func removeRule(id: Int64) {
        self.lock.lock()
        self.config.filters.removeAll { $0.id == id }
        self.storage.save(self.config)
        self.engine.compile(config: self.config)
        self.lock.unlock()
    }

    public func toggleRule(id: Int64) {
        self.lock.lock()
        if let idx = self.config.filters.firstIndex(where: { $0.id == id }) {
            self.config.filters[idx].enabled.toggle()
            self.storage.save(self.config)
            self.engine.compile(config: self.config)
        }
        self.lock.unlock()
    }

    public func addExclusion(dialogId: Int64) {
        self.lock.lock()
        if !self.config.exclusions.contains(dialogId) {
            self.config.exclusions.append(dialogId)
            self.storage.save(self.config)
            self.engine.compile(config: self.config)
        }
        self.lock.unlock()
    }

    public func removeExclusion(dialogId: Int64) {
        self.lock.lock()
        self.config.exclusions.removeAll { $0 == dialogId }
        self.storage.save(self.config)
        self.engine.compile(config: self.config)
        self.lock.unlock()
    }

    public func importConfig(from data: Data, merge: Bool) throws -> (filtersAdded: Int, exclusionsAdded: Int) {
        let decoder = JSONDecoder()
        let imported = try decoder.decode(AyuFiltersConfig.self, from: data)

        self.lock.lock()
        defer { self.lock.unlock() }

        var finalFilters: [AyuFilterRule]
        var finalExclusions: [Int64]

        if merge {
            var existingMap = [Int64: AyuFilterRule]()
            for f in self.config.filters {
                existingMap[f.id] = f
            }
            for f in imported.filters {
                existingMap[f.id] = f
            }
            finalFilters = Array(existingMap.values).sorted { $0.id < $1.id }

            var exclSet = Set(self.config.exclusions)
            for e in imported.exclusions {
                exclSet.insert(e)
            }
            finalExclusions = Array(exclSet)
        } else {
            finalFilters = imported.filters
            finalExclusions = imported.exclusions
        }

        self.config.filters = finalFilters
        self.config.exclusions = finalExclusions
        if imported.autoClickButtonsEnabled {
            self.config.autoClickButtonsEnabled = true
        }

        self.storage.save(self.config)
        self.engine.compile(config: self.config)

        return (imported.filters.count, imported.exclusions.count)
    }

    public func shouldFilter(message: Message, context: AccountContext) -> Bool {
        guard self.config.isEnabled else {
            return false
        }

        let peerId = message.id.peerId
        let dialogId = peerId.toInt64()
        var altDialogId: Int64? = nil
        switch peerId.namespace {
        case Namespaces.Peer.CloudUser:
            altDialogId = peerId.id._internalGetInt64Value()
        case Namespaces.Peer.CloudGroup:
            altDialogId = -peerId.id._internalGetInt64Value()
        case Namespaces.Peer.CloudChannel:
            altDialogId = -(1000000000000 + peerId.id._internalGetInt64Value())
        case Namespaces.Peer.SecretChat:
            altDialogId = peerId.id._internalGetInt64Value()
        default:
            break
        }

        // Extract message text (in Telegram-iOS, captions are stored in message.text)
        var messageText = message.text

        // Also check media filename
        for media in message.media {
            if let file = media as? TelegramMediaFile {
                for attr in file.attributes {
                    if let filenameAttr = attr as? TelegramMediaFileAttributeFilename {
                        if messageText.isEmpty {
                            messageText = filenameAttr.fileName
                        } else {
                            messageText += "\n" + filenameAttr.fileName
                        }
                        break
                    }
                }
            }
        }

        // Extract button titles and actions from ReplyMarkupMessageAttribute
        var buttonTitles: [String] = []
        var callbackButtons: [(title: String, data: MemoryBuffer)] = []

        for attribute in message.attributes {
            if let replyMarkup = attribute as? ReplyMarkupMessageAttribute {
                for row in replyMarkup.rows {
                    for button in row.buttons {
                        buttonTitles.append(button.title)
                        if case let .callback(_, data) = button.action {
                            callbackButtons.append((title: button.title, data: data))
                        }
                    }
                }
            }
        }

        guard let match = self.engine.shouldFilter(dialogId: dialogId, altDialogId: altDialogId, text: messageText, buttonTitles: buttonTitles) else {
            return false
        }

        // Safe button auto-click handling (Phase 5.4)
        if match.shouldAutoClickButton && !callbackButtons.isEmpty {
            self.safeAutoClick(messageId: message.id, buttons: callbackButtons, targetPattern: match.targetButtonPattern, context: context)
        }

        return true
    }

    private func safeAutoClick(messageId: MessageId, buttons: [(title: String, data: MemoryBuffer)], targetPattern: String?, context: AccountContext) {
        self.lock.lock()
        // Deduplication: click at most once per message ID
        guard !self.clickedMessageIds.contains(messageId) else {
            self.lock.unlock()
            return
        }

        // Rate-limiting: minimum 2.0s cooldown between auto-clicks to prevent spam
        let now = Date().timeIntervalSince1970
        guard now - self.lastClickTime > 2.0 else {
            self.lock.unlock()
            return
        }

        self.clickedMessageIds.insert(messageId)
        if self.clickedMessageIds.count > 1000 {
            // Keep memory bound
            self.clickedMessageIds.removeAll()
        }
        self.lastClickTime = now
        self.lock.unlock()

        // Select the matching button or the first callback button
        var chosenButton: (title: String, data: MemoryBuffer)? = nil
        if let pattern = targetPattern, !pattern.isEmpty {
            chosenButton = buttons.first { $0.title.range(of: pattern, options: .caseInsensitive) != nil }
        }
        if chosenButton == nil {
            chosenButton = buttons.first
        }

        guard let target = chosenButton else {
            return
        }

        DispatchQueue.main.async {
            let engine = TelegramEngine(account: context.account)
            let _ = engine.messages.requestMessageActionCallback(messageId: messageId, isGame: false, password: nil, data: target.data).startStrict()
        }
    }
}
