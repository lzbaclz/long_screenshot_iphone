import Foundation

/// Localize only at presentation boundaries; persisted reasons remain stable canonical keys.
public enum CaptureMessageLocalization {
    public static func text(_ canonicalReason: String, bundle: Bundle = .main) -> String {
        // Earlier records used wording that could imply an involuntary stop.
        // ReplayKit's finished callback also follows the user's system Stop action.
        if canonicalReason == "捕捉已由系统结束。" {
            return text("广播已结束。", bundle: bundle)
        }
        // Composite terminal reasons keep the real underlying storage/system
        // error. Localize each stable component instead of losing that cause.
        for prefix in ["未写入可用画面。", "未确认连续滚动，仅保留一张完整单屏。请查看后重新捕捉长图。"] {
            if canonicalReason.hasPrefix(prefix + " ") {
                let suffix = String(canonicalReason.dropFirst(prefix.count + 1))
                return bundle.localizedString(forKey: prefix, value: prefix, table: nil) + " " + text(suffix, bundle: bundle)
            }
        }
        let formats = [
            ("已达到设置的 ", " 屏上限。", "已达到设置的 %lld 屏上限。"),
            ("停止滑动 ", " 秒，已完成捕捉。", "停止滑动 %lld 秒，已完成捕捉。")
        ]
        for (prefix, suffix, key) in formats
        where canonicalReason.hasPrefix(prefix) && canonicalReason.hasSuffix(suffix) {
            if let count = Int64(canonicalReason.dropFirst(prefix.count).dropLast(suffix.count)) {
                let format = bundle.localizedString(forKey: key, value: key, table: nil)
                return String(format: format, locale: Locale.current, count)
            }
        }
        return bundle.localizedString(forKey: canonicalReason, value: canonicalReason, table: nil)
    }
}
