import Foundation
import GGCore

public enum GGAyuFiltersSettings {
    public static let enabled = GGSetting<Bool>("ayuFilters.enabled", default: true)
    public static let autoClickButtons = GGSetting<Bool>("ayuFilters.autoClickButtons", default: false)
}
