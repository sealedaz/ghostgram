import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ItemListUI
import PresentationDataUtils
import AlertUI
import PromptUI
import GGCore

private final class AyuFiltersListArguments {
    let context: AccountContext
    let addRule: () -> Void
    let selectRule: (AyuFilterRule) -> Void
    let toggleRule: (Int64) -> Void
    let removeExclusion: (Int64) -> Void

    init(
        context: AccountContext,
        addRule: @escaping () -> Void,
        selectRule: @escaping (AyuFilterRule) -> Void,
        toggleRule: @escaping (Int64) -> Void,
        removeExclusion: @escaping (Int64) -> Void
    ) {
        self.context = context
        self.addRule = addRule
        self.selectRule = selectRule
        self.toggleRule = toggleRule
        self.removeExclusion = removeExclusion
    }
}

private enum AyuFiltersListSection: Int {
    case add = 0
    case sharedFilters = 1
    case chatFilters = 2
    case exclusions = 3
}

private enum AyuFiltersListEntry: ItemListNodeEntry {
    case addRule(String)
    case sharedHeader(String)
    case sharedFilter(Int, AyuFilterRule)
    case chatHeader(String)
    case chatFilter(Int, AyuFilterRule)
    case exclusionsHeader(String)
    case exclusionItem(Int, Int64)
    case empty(String)

    var section: ItemListSectionId {
        switch self {
        case .addRule:
            return AyuFiltersListSection.add.rawValue
        case .sharedHeader, .sharedFilter:
            return AyuFiltersListSection.sharedFilters.rawValue
        case .chatHeader, .chatFilter:
            return AyuFiltersListSection.chatFilters.rawValue
        case .exclusionsHeader, .exclusionItem:
            return AyuFiltersListSection.exclusions.rawValue
        case .empty:
            return AyuFiltersListSection.sharedFilters.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case .addRule:
            return 0
        case .sharedHeader:
            return 1000
        case let .sharedFilter(index, _):
            return 1001 + index
        case .chatHeader:
            return 2000
        case let .chatFilter(index, _):
            return 2001 + index
        case .exclusionsHeader:
            return 3000
        case let .exclusionItem(index, _):
            return 3001 + index
        case .empty:
            return 9999
        }
    }

    static func ==(lhs: AyuFiltersListEntry, rhs: AyuFiltersListEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.addRule(lhsText), .addRule(rhsText)):
            return lhsText == rhsText
        case let (.sharedHeader(lhsText), .sharedHeader(rhsText)):
            return lhsText == rhsText
        case let (.sharedFilter(lhsIndex, lhsRule), .sharedFilter(rhsIndex, rhsRule)):
            return lhsIndex == rhsIndex && lhsRule == rhsRule
        case let (.chatHeader(lhsText), .chatHeader(rhsText)):
            return lhsText == rhsText
        case let (.chatFilter(lhsIndex, lhsRule), .chatFilter(rhsIndex, rhsRule)):
            return lhsIndex == rhsIndex && lhsRule == rhsRule
        case let (.exclusionsHeader(lhsText), .exclusionsHeader(rhsText)):
            return lhsText == rhsText
        case let (.exclusionItem(lhsIndex, lhsId), .exclusionItem(rhsIndex, rhsId)):
            return lhsIndex == rhsIndex && lhsId == rhsId
        case let (.empty(lhsText), .empty(rhsText)):
            return lhsText == rhsText
        default:
            return false
        }
    }

    static func <(lhs: AyuFiltersListEntry, rhs: AyuFiltersListEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! AyuFiltersListArguments
        switch self {
        case let .addRule(text):
            return ItemListActionItem(
                presentationData: presentationData,
                title: text,
                kind: .generic,
                alignment: .natural,
                sectionId: self.section,
                style: .blocks,
                action: {
                    args.addRule()
                }
            )
        case let .sharedHeader(text), let .chatHeader(text), let .exclusionsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .sharedFilter(_, rule), let .chatFilter(_, rule):
            return ItemListSwitchItem(
                presentationData: presentationData,
                title: rule.text,
                value: rule.enabled,
                type: .regular,
                sectionId: self.section,
                style: .blocks,
                updated: { _ in
                    args.toggleRule(rule.id)
                },
                action: {
                    args.selectRule(rule)
                }
            )
        case let .exclusionItem(_, dialogId):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                title: "Dialog ID: \(dialogId)",
                label: "Remove",
                sectionId: self.section,
                style: .blocks,
                action: {
                    args.removeExclusion(dialogId)
                }
            )
        case let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func makeAyuFiltersListScreen(context: AccountContext) -> ViewController {
    let updateSignal = ValuePromise<Void>(Void(), ignoreRepeated: false)

    var selectRuleImpl: ((AyuFilterRule, ItemListController?) -> Void)?
    var addRuleImpl: ((ItemListController?) -> Void)?

    let arguments = AyuFiltersListArguments(
        context: context,
        addRule: {
            addRuleImpl?(nil)
        },
        selectRule: { rule in
            selectRuleImpl?(rule, nil)
        },
        toggleRule: { id in
            AyuFiltersManager.shared.toggleRule(id: id)
            updateSignal.set(Void())
        },
        removeExclusion: { dialogId in
            AyuFiltersManager.shared.removeExclusion(dialogId: dialogId)
            updateSignal.set(Void())
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, updateSignal.get())
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let config = AyuFiltersManager.shared.config
        var entries: [AyuFiltersListEntry] = []

        entries.append(.addRule(GGStrings.AyuFilters.dialogAdd))

        let sharedRules = config.filters.filter { $0.dialogId == nil || $0.dialogId == 0 }
        let chatRules = config.filters.filter { $0.dialogId != nil && $0.dialogId != 0 }

        if !sharedRules.isEmpty {
            entries.append(.sharedHeader("Shared Filters (\(sharedRules.count))"))
            for (index, rule) in sharedRules.enumerated() {
                entries.append(.sharedFilter(index, rule))
            }
        }

        if !chatRules.isEmpty {
            entries.append(.chatHeader("Per-Chat Filters (\(chatRules.count))"))
            for (index, rule) in chatRules.enumerated() {
                entries.append(.chatFilter(index, rule))
            }
        }

        if !config.exclusions.isEmpty {
            entries.append(.exclusionsHeader("Exclusions (\(config.exclusions.count))"))
            for (index, dId) in config.exclusions.enumerated() {
                entries.append(.exclusionItem(index, dId))
            }
        }

        if sharedRules.isEmpty && chatRules.isEmpty {
            entries.append(.empty(GGStrings.AyuFilters.empty))
        }

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(GGStrings.AyuFilters.list),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks,
            animateChanges: true
        )
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)

    selectRuleImpl = { [weak controller] rule, _ in
        guard let controller = controller else { return }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        let items: [ActionSheetItem] = [
            ActionSheetTextItem(title: "\(rule.text)\n(ID: \(rule.id))", parseMarkdown: false),
            ActionSheetButtonItem(title: rule.enabled ? "Disable" : "Enable", color: .accent, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                AyuFiltersManager.shared.toggleRule(id: rule.id)
                updateSignal.set(Void())
            }),
            ActionSheetButtonItem(title: GGStrings.AyuFilters.delete, color: .destructive, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                AyuFiltersManager.shared.removeRule(id: rule.id)
                updateSignal.set(Void())
            })
        ]
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })
            ])
        ])
        controller.present(actionSheet, in: .window(.root))
    }

    addRuleImpl = { [weak controller] _ in
        guard let controller = controller else { return }
        let prompt = promptController(
            context: context,
            text: GGStrings.AyuFilters.dialogTitle,
            value: nil,
            placeholder: GGStrings.AyuFilters.dialogPlaceholder,
            characterLimit: 1000,
            apply: { value in
                guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                    return
                }
                let rule = AyuFilterRule(
                    id: Int64(Date().timeIntervalSince1970 * 1000),
                    dialogId: nil,
                    text: value,
                    reversed: false,
                    caseInsensitive: true,
                    enabled: true
                )
                AyuFiltersManager.shared.addRule(rule)
                updateSignal.set(Void())
            }
        )
        controller.present(prompt, in: .window(.root))
    }

    return controller
}
