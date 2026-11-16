import Foundation
import UIKit
import Display
import AccountContext
import ContextUI
import AlertUI
import PresentationDataUtils
import AppBundle
import UndoUI
import PromptUI
import GGCore
import GGHooks
import GGSettingsUI

public enum AyuFiltersMenu {
    public static let tab = GGMenuTabID("messages.ayuFilters")
    public static let mainSection = GGMenuSectionID("messages.ayuFilters.main")

    public static func register() {
        // 1. Register AyuFilters settings tab
        GGMenuRegistry.register(tab: GGMenuTabDescriptor(
            id: self.tab,
            section: .messagesTabs,
            order: 250,
            title: { GGStrings.AyuFilters.title },
            info: { GGStrings.AyuFilters.toggleInfo },
            icon: .bundle("Chat/Context Menu/Restrict"),
            emoji: "🛡️"
        ))

        GGMenuRegistry.register(section: GGMenuSectionDescriptor(
            id: self.mainSection,
            screen: .tab(self.tab),
            order: 100,
            header: { GGStrings.AyuFilters.title }
        ))

        // Toggle: Enable Filters
        GGMenuRegistry.register(GGMenuRow(
            id: "ayuFilters.isEnabled",
            section: self.mainSection,
            order: 100,
            title: { GGStrings.AyuFilters.toggle },
            subtitle: { GGStrings.AyuFilters.toggleInfo },
            kind: .custom(build: { _ in nil }, isChanged: { _ in false }, getDisplayValue: { _ in
                AyuFiltersManager.shared.config.isEnabled ? "ON" : "OFF"
            }, action: { _, _ in
                let current = AyuFiltersManager.shared.config.isEnabled
                AyuFiltersManager.shared.setEnabled(!current)
            })
        ))

        // Toggle: Auto-click Buttons (<button>)
        GGMenuRegistry.register(GGMenuRow(
            id: "ayuFilters.autoClickButtons",
            section: self.mainSection,
            order: 200,
            title: { GGStrings.AyuFilters.autoClick },
            subtitle: { GGStrings.AyuFilters.autoClickInfo },
            kind: .custom(build: { _ in nil }, isChanged: { _ in false }, getDisplayValue: { _ in
                AyuFiltersManager.shared.config.autoClickButtonsEnabled ? "ON" : "OFF"
            }, action: { _, _ in
                let current = AyuFiltersManager.shared.config.autoClickButtonsEnabled
                AyuFiltersManager.shared.setAutoClickButtonsEnabled(!current)
            })
        ))

        // Open Filters List Screen
        GGMenuRegistry.register(GGMenuRow(
            id: "ayuFilters.openFiltersList",
            section: self.mainSection,
            order: 300,
            title: { GGStrings.AyuFilters.list },
            kind: .navigation(destination: { context in
                return makeAyuFiltersListScreen(context: context)
            })
        ))

        // Action: Import from URL
        GGMenuRegistry.register(GGMenuRow(
            id: "ayuFilters.importUrl",
            section: self.mainSection,
            order: 400,
            title: { GGStrings.AyuFilters.importUrl },
            kind: .action({ context, controller in
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let clipboardString = UIPasteboard.general.string
                let suggestedValue: String? = (clipboardString?.contains("dpaste") == true || clipboardString?.contains("github") == true || clipboardString?.contains("pastebin") == true || clipboardString?.contains("nekobin") == true) ? clipboardString : nil

                let prompt = promptController(
                    context: context,
                    text: GGStrings.AyuFilters.importUrl,
                    subtitle: "dpaste.com, gist.githubusercontent.com, pastebin.com, nekobin.com",
                    value: suggestedValue,
                    placeholder: "https://pastebin.com/raw/...",
                    characterLimit: 2048,
                    apply: { urlString in
                        guard let raw = urlString?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return }
                        AyuFiltersImportController.fetchAndPreview(
                            urlString: raw,
                            context: context,
                            present: { c in controller.present(c, in: .window(.root)) },
                            onComplete: {
                                let toast = UndoOverlayController(
                                    presentationData: presentationData,
                                    content: .info(title: nil, text: "Filters imported successfully", timeout: nil, customUndoText: nil),
                                    elevatedLayout: false,
                                    action: { _ in false }
                                )
                                context.sharedContext.mainWindow?.present(toast, on: .root)
                            }
                        )
                    }
                )
                controller.present(prompt, in: .window(.root))
            })
        ))

        // Action: Import from Clipboard
        GGMenuRegistry.register(GGMenuRow(
            id: "ayuFilters.importClipboard",
            section: self.mainSection,
            order: 500,
            title: { GGStrings.AyuFilters.importClipboard },
            kind: .action({ context, _ in
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                guard let string = UIPasteboard.general.string, let data = string.data(using: .utf8) else {
                    let alert = textAlertController(
                        context: context,
                        updatedPresentationData: nil,
                        title: GGStrings.AyuFilters.importError,
                        text: "Clipboard does not contain valid text.",
                        actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
                    )
                    context.sharedContext.mainWindow?.present(alert, on: .root)
                    return
                }

                do {
                    let result = try AyuFiltersManager.shared.importConfig(from: data, merge: true)
                    let text = GGStrings.AyuFilters.importSuccess(filters: result.filtersAdded, exclusions: result.exclusionsAdded)
                    let toast = UndoOverlayController(
                        presentationData: presentationData,
                        content: .info(title: nil, text: text, timeout: nil, customUndoText: nil),
                        elevatedLayout: false,
                        action: { _ in false }
                    )
                    context.sharedContext.mainWindow?.present(toast, on: .root)
                } catch {
                    let alert = textAlertController(
                        context: context,
                        updatedPresentationData: nil,
                        title: GGStrings.AyuFilters.importError,
                        text: "Failed to parse JSON: \(error.localizedDescription)",
                        actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
                    )
                    context.sharedContext.mainWindow?.present(alert, on: .root)
                }
            })
        ))

        // Action: Export Filters
        GGMenuRegistry.register(GGMenuRow(
            id: "ayuFilters.exportJson",
            section: self.mainSection,
            order: 600,
            title: { GGStrings.AyuFilters.export },
            kind: .action({ context, _ in
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                if let json = AyuFiltersStorage.shared.exportJsonString() {
                    UIPasteboard.general.string = json
                    let toast = UndoOverlayController(
                        presentationData: presentationData,
                        content: .info(title: nil, text: "JSON copied to clipboard", timeout: nil, customUndoText: nil),
                        elevatedLayout: false,
                        action: { _ in false }
                    )
                    context.sharedContext.mainWindow?.present(toast, on: .root)
                }
            })
        ))

        // 2. Register Context Menu Item: "Add to AyuFilters" (Phase 5.5)
        GGMessageMenuHooks.items.register({ menuContext in
            return self.messageMenuItems(menuContext)
        }, order: 250)
    }

    private static func messageMenuItems(_ menuContext: GGMessageMenuContext) -> [GGMessageMenuEntry] {
        guard let message = menuContext.messages.first, !message.text.isEmpty else {
            return []
        }

        let context = menuContext.context
        let text = message.text
        let dialogId = message.id.peerId.toInt64()

        let item = ContextMenuItem.action(ContextMenuActionItem(
            text: GGStrings.AyuFilters.quickAdd,
            icon: { theme in
                generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Restrict"), color: theme.contextMenu.primaryColor)
            },
            action: { _, f in
                f(.default)
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let actionSheet = ActionSheetController(presentationData: presentationData)
                actionSheet.setItemGroups([
                    ActionSheetItemGroup(items: [
                        ActionSheetTextItem(title: "Add Filter Rule:\n\"\(text.prefix(60))\(text.count > 60 ? "..." : "")\"", parseMarkdown: false),
                        ActionSheetButtonItem(title: "Add Global Filter", color: .accent, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                            let rule = AyuFilterRule(
                                id: Int64(Date().timeIntervalSince1970 * 1000),
                                dialogId: nil,
                                text: "<type>contains</type>\(text)",
                                reversed: false,
                                caseInsensitive: true,
                                enabled: true
                            )
                            AyuFiltersManager.shared.addRule(rule)
                            let toast = UndoOverlayController(
                                presentationData: presentationData,
                                content: .info(title: nil, text: "Added global filter rule", timeout: nil, customUndoText: nil),
                                elevatedLayout: false,
                                action: { _ in false }
                            )
                            context.sharedContext.mainWindow?.present(toast, on: .root)
                        }),
                        ActionSheetButtonItem(title: GGStrings.AyuFilters.dialogChatOnly, color: .accent, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                            let rule = AyuFilterRule(
                                id: Int64(Date().timeIntervalSince1970 * 1000),
                                dialogId: dialogId,
                                text: "<type>contains</type>\(text)",
                                reversed: false,
                                caseInsensitive: true,
                                enabled: true
                            )
                            AyuFiltersManager.shared.addRule(rule)
                            let toast = UndoOverlayController(
                                presentationData: presentationData,
                                content: .info(title: nil, text: "Added per-chat filter rule", timeout: nil, customUndoText: nil),
                                elevatedLayout: false,
                                action: { _ in false }
                            )
                            context.sharedContext.mainWindow?.present(toast, on: .root)
                        })
                    ]),
                    ActionSheetItemGroup(items: [
                        ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, action: { [weak actionSheet] in
                            actionSheet?.dismissAnimated()
                        })
                    ])
                ])
                context.sharedContext.mainWindow?.present(actionSheet, on: .root)
            }
        ))

        return [GGMessageMenuEntry(position: .bottom, item: item)]
    }
}
