import UIKit
import Foundation
import CoreFoundation

/// PreferenceLoader resolves this exact Objective-C runtime name.
@objc(NDASettingsController)
final class NDASettingsController: PSListController {
    private let preferenceDomain = "com.tsangbaby.noticedeleteanimation" as CFString
    private var cachedSpecifiers: NSMutableArray?

    override var specifiers: NSMutableArray! {
        get {
            let items = cachedSpecifiers ?? NDAMakeSettingsSpecifiers(self, diagnosticText())
            cachedSpecifiers = items
            // Preferences also reads its own _specifiers ivar for table sections.
            // A Swift-only cache is not the superclass's table model.
            super.specifiers = items
            return items
        }
        set {
            cachedSpecifiers = newValue
            super.specifiers = newValue
        }
    }

    override func viewDidLoad() {
        // Populate the actual Preferences model before UIKit builds its table.
        specifiers = NDAMakeSettingsSpecifiers(self, diagnosticText())
        super.viewDidLoad()
        title = "NoticeDeleteAnimation"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .refresh,
            target: self,
            action: #selector(refreshDiagnostics)
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshDiagnostics()
    }

    @objc(nda_readEnabled:)
    func readEnabled(_ specifier: PSSpecifier) -> NSNumber {
        CFPreferencesAppSynchronize(preferenceDomain)
        guard let value = CFPreferencesCopyAppValue("Enabled" as CFString, preferenceDomain),
              CFGetTypeID(value) == CFBooleanGetTypeID(),
              let number = value as? NSNumber else {
            return NSNumber(value: true)
        }
        return NSNumber(value: number.boolValue)
    }

    @objc(nda_setEnabled:specifier:)
    func setEnabled(_ value: NSNumber, specifier: PSSpecifier) {
        // This is the only key this bundle writes. Diagnostics remain read-only.
        CFPreferencesSetAppValue(
            "Enabled" as CFString,
            value.boolValue ? kCFBooleanTrue : kCFBooleanFalse,
            preferenceDomain
        )
        let synchronized = CFPreferencesAppSynchronize(preferenceDomain)
        if !synchronized {
            let alert = UIAlertController(
                title: "无法同步设置",
                message: "偏好设置尚未确认写入磁盘。请重新打开此页面并检查开关状态。",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "好", style: .default))
            present(alert, animated: true)
        }
        // Runtime reads Enabled at each deletion; no respring/Darwin observer needed.
    }

    @objc(nda_refreshDiagnostics)
    func refreshDiagnostics() {
        cachedSpecifiers = nil
        reloadSpecifiers()
    }

    private func diagnosticText() -> String {
        let synchronized = CFPreferencesAppSynchronize(preferenceDomain)
        let summary = stringPreference("DiagnosticsSummary", limit: 6000)
        let updated = stringPreference("DiagnosticsUpdated", limit: 160)
        var lines: [String] = []
        if !synchronized {
            lines.append("偏好同步失败；以下可能是缓存数据。")
        }
        if let summary = summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(summary)
        } else {
            lines.append("尚无 SpringBoard 诊断摘要。可能尚未加载插件、尚未写入，或偏好域不可读；此页面本身不能证明 hook 已生效。")
        }
        lines.append("更新时间：\(updated ?? "尚无记录")")
        if let value = CFPreferencesCopyAppValue("DiagnosticsPID" as CFString, preferenceDomain),
           CFGetTypeID(value) == CFNumberGetTypeID(),
           let number = value as? NSNumber {
            let pid = number.doubleValue
            if pid.isFinite, pid > 0, pid <= Double(Int32.max), pid.rounded() == pid {
                lines.append("记录进程 PID：\(Int64(pid))")
            }
        }
        lines.append("以上为上次保存的状态；PID 可能属于重启前的旧 SpringBoard，不是实时注入验证。请结合更新时间判断。")
        return lines.joined(separator: "\n\n")
    }

    private func stringPreference(_ key: String, limit: Int) -> String? {
        guard let value = CFPreferencesCopyAppValue(key as CFString, preferenceDomain),
              CFGetTypeID(value) == CFStringGetTypeID(),
              let text = value as? String else { return nil }
        // Bound Settings rendering; never enumerate the preferences domain or log values.
        let bounded = String(text.prefix(limit))
        return text.count > limit ? bounded + "\n（摘要已截断）" : bounded
    }
}
