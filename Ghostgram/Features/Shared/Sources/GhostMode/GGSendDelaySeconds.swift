import Foundation

/// «Задержка» of the send delay: one value for every message since 2026-10-27 (owner: two sliders,
/// text and media, became one). Foundation only: host-tested.
public enum GGSendDelaySeconds {
    /// The server sends at once anything scheduled less than ~10 s ahead; 12 keeps a margin.
    public static let range: ClosedRange<Double> = 12.0 ... 180.0
    /// The larger of the two old defaults (text 12 s, media 20 s): nothing gets sent sooner.
    public static let defaultValue: Double = 20.0

    static let oldTextDefault: Double = 12.0
    static let oldMediaDefault: Double = 20.0

    public static func clamped(_ value: Double) -> Double {
        if value.isNaN {
            return GGSendDelaySeconds.defaultValue
        }
        return min(GGSendDelaySeconds.range.upperBound, max(GGSendDelaySeconds.range.lowerBound, value))
    }

    /// Dynamic stealth delay formula (Phase 3.1):
    /// - text: +12s from current time
    /// - media (photo, video, file): max(6, ceil(fileSizeBytes / 1024.0 / 1024.0 * 4.5))
    public static func dynamicDelay(hasMedia: Bool, fileSizeBytes: Int64?) -> Double {
        if !hasMedia {
            return 12.0
        }
        let bytes = Double(fileSizeBytes ?? 0)
        let mb = bytes / (1024.0 * 1024.0)
        return max(6.0, ceil(mb * 4.5))
    }

    /// Builds ≤ 185: `sendDelay.textSeconds` and `sendDelay.mediaSeconds` (nil = never stored =
    /// their defaults) → the larger of the two. nil when neither was stored (the new default is
    /// already the larger default).
    public static func merged(text: Double?, media: Double?) -> Double? {
        if text == nil && media == nil {
            return nil
        }
        let larger = max(text ?? GGSendDelaySeconds.oldTextDefault, media ?? GGSendDelaySeconds.oldMediaDefault)
        return GGSendDelaySeconds.clamped(larger)
    }
}
