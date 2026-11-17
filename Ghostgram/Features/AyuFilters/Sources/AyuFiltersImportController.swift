import Foundation
import UIKit
import Display
import AccountContext
import AlertUI
import PresentationDataUtils
import GGCore

public enum AyuFiltersImportController {
    private static let allowedHosts: Set<String> = [
        "dpaste.com",
        "gist.githubusercontent.com",
        "gist.github.com",
        "pastebin.com",
        "nekobin.com"
    ]

    public static func normalizeURLString(_ urlString: String) -> URL? {
        var raw = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.lowercased().hasPrefix("http://") && !raw.lowercased().hasPrefix("https://") {
            raw = "https://" + raw
        }

        guard let url = URL(string: raw), let host = url.host?.lowercased() else {
            return nil
        }

        let isAllowed = self.allowedHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) })
        guard isAllowed else {
            return nil
        }

        // Convert page URLs to raw content URLs
        if host.contains("gist.github.com") && !host.contains("gist.githubusercontent.com") {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !path.isEmpty {
                let cleanPath = path.hasSuffix("/raw") ? String(path.dropLast(4)) : path
                return URL(string: "https://gist.githubusercontent.com/\(cleanPath)/raw")
            }
        } else if host.contains("pastebin.com") && !url.path.contains("/raw/") {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !path.isEmpty {
                return URL(string: "https://pastebin.com/raw/\(path)")
            }
        } else if host.contains("dpaste.com") && !url.path.hasSuffix(".txt") && !url.path.hasSuffix("/raw") {
            return URL(string: raw + ".txt")
        } else if host.contains("nekobin.com") && !url.path.contains("/raw/") {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !path.isEmpty {
                return URL(string: "https://nekobin.com/raw/\(path)")
            }
        }

        return url
    }

    public static func fetchAndPreview(urlString: String, context: AccountContext, present: @escaping (ViewController) -> Void, onComplete: @escaping () -> Void) {
        guard let url = self.normalizeURLString(urlString) else {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let alert = textAlertController(
                context: context,
                updatedPresentationData: nil,
                title: GGStrings.AyuFilters.importError,
                text: "URL must be from dpaste.com, gist.githubusercontent.com, pastebin.com, or nekobin.com.",
                actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
            )
            present(alert)
            return
        }

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                guard let data = data, error == nil else {
                    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                    let alert = textAlertController(
                        context: context,
                        updatedPresentationData: nil,
                        title: GGStrings.AyuFilters.importError,
                        text: error?.localizedDescription ?? "Network error",
                        actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
                    )
                    present(alert)
                    return
                }

                do {
                    let decoder = JSONDecoder()
                    let previewConfig = try decoder.decode(AyuFiltersConfig.self, from: data)

                    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                    let previewText = GGStrings.AyuFilters.importPreview(filters: "\(previewConfig.filters.count)", exclusions: "\(previewConfig.exclusions.count)")

                    let alert = textAlertController(
                        context: context,
                        updatedPresentationData: nil,
                        title: GGStrings.AyuFilters.importUrl,
                        text: previewText,
                        actions: [
                            TextAlertAction(type: .defaultAction, title: GGStrings.AyuFilters.importMerge, action: {
                                do {
                                    let _ = try AyuFiltersManager.shared.importConfig(from: data, merge: true)
                                    onComplete()
                                } catch {}
                            }),
                            TextAlertAction(type: .destructiveAction, title: GGStrings.AyuFilters.importReplace, action: {
                                do {
                                    let _ = try AyuFiltersManager.shared.importConfig(from: data, merge: false)
                                    onComplete()
                                } catch {}
                            }),
                            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {})
                        ]
                    )
                    present(alert)
                } catch {
                    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                    let alert = textAlertController(
                        context: context,
                        updatedPresentationData: nil,
                        title: GGStrings.AyuFilters.importError,
                        text: "Invalid AyuGram JSON v2 format: \(error.localizedDescription)",
                        actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
                    )
                    present(alert)
                }
            }
        }
        task.resume()
    }
}
