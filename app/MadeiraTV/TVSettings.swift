// SPDX-License-Identifier: GPL-3.0-or-later
// Madeira Converter Exception: see LICENSE-EXCEPTION.md
//
// tvOS settings persisted in UserDefaults. Driven from TVSettingsView and
// read by the HUD and launch path.

import SwiftUI

enum TVSettings {
    static let showHudKey = "tv.showHUD"
    static let showHudDefault = true

    static var showHUD: Bool {
        get { UserDefaults.standard.object(forKey: showHudKey) as? Bool ?? showHudDefault }
        set { UserDefaults.standard.set(newValue, forKey: showHudKey) }
    }

    static let hudMonospaceKey = "tv.hudMonospace"
    /// FPS-smoothing divisor; keeps HUD updates from fighting the renderer.
    /// 0 = HUD never shows during gameplay (user read it as "clean screen").
    static var hudMonospace: Bool {
        get { UserDefaults.standard.object(forKey: hudMonospaceKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: hudMonospaceKey) }
    }

    static let launchBreadcrumbsKey = "tv.launchBreadcrumbs"
    /// When enabled, launch() also writes per-phase breadcrumbs to crash.log
    /// (default on; turning off lightens logging when diagnosing is over).
    static var launchBreadcrumbs: Bool {
        get { UserDefaults.standard.object(forKey: launchBreadcrumbsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: launchBreadcrumbsKey) }
    }
}

struct TVSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(TVSettings.showHudKey) private var showHUD = TVSettings.showHudDefault
    @AppStorage(TVSettings.hudMonospaceKey) private var hudMonospace = true
    @AppStorage(TVSettings.launchBreadcrumbsKey) private var launchBreadcrumbs = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Display") {
                    Toggle("Show FPS / status HUD over games", isOn: $showHUD)
                    Toggle("Monospace HUD font", isOn: $hudMonospace)
                }
                Section("Diagnostics") {
                    Toggle("Log launch phases to crash.log", isOn: $launchBreadcrumbs)
                }
                Section("Wine") {
                    Button("Stop wine if running") {
                        wineserver_stop()
                    }
                    .disabled(wineserver_is_running() == 0 && wine_process_is_running() == 0)
                }
                Section {
                    Text("Build b256e5a (tvOS target). HUD reads DXMT present counter.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}