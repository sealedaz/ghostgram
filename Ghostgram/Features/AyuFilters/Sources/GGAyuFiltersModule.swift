import Foundation
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
}
