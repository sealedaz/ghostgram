import Foundation
import Display
import Postbox
import TelegramCore
import AccountContext
import GGCore
import GGHooks

public enum GGAyuFiltersModule {
    public static func register() {
        assert(Thread.isMainThread)

        // 1. Hook message filtering into chat screen display (Phase 5.3)
        GGChatScreenHooks.hidesMessage.register({ message, context, _ in
            return AyuFiltersManager.shared.shouldFilter(message: message, context: context)
        })

        // 2. Register UI settings and context menu items (Phase 5.5)
        AyuFiltersMenu.register()
    }

    @discardableResult
    public static func handleDeepLink(_ url: URL, context: AccountContext, navigationController: NavigationController?) -> Bool {
        guard let host = url.host?.lowercased(), host == "ayu" else {
            return false
        }

        let path = url.path.lowercased()
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        func param(_ name: String) -> String? {
            return queryItems.first(where: { $0.name.lowercased() == name.lowercased() })?.value
        }

        if path.hasPrefix("/filters/import") {
            if let importUrl = param("url"), !importUrl.isEmpty {
                let present: (ViewController) -> Void = { vc in
                    if let navigationController {
                        navigationController.pushViewController(vc)
                    } else {
                        context.sharedContext.presentGlobalController(vc, nil)
                    }
                }
                AyuFiltersImportController.fetchAndPreview(
                    urlString: importUrl,
                    context: context,
                    present: present,
                    onComplete: {}
                )
                return true
            }
        } else if path.hasPrefix("/filters/add") {
            let controller = makeAyuFiltersListScreen(context: context)
            if let navigationController {
                navigationController.pushViewController(controller)
            } else {
                context.sharedContext.presentGlobalController(controller, nil)
            }
            if let text = param("text"), !text.isEmpty {
                AyuFiltersManager.shared.addRule(pattern: text)
            }
            return true
        } else if path.hasPrefix("/filters") || path.hasPrefix("/settings") || path.isEmpty {
            let controller = makeAyuFiltersListScreen(context: context)
            if let navigationController {
                navigationController.pushViewController(controller)
            } else {
                context.sharedContext.presentGlobalController(controller, nil)
            }
            return true
        }

        return false
    }
}
