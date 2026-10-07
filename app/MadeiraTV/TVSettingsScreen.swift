// SPDX-License-Identifier: GPL-3.0-or-later
// Madeira Converter Exception: see LICENSE-EXCEPTION.md
//
// tvOS Settings: account, display (HUD + quiet), performance (JIT pool),
// diagnostics (verbose logging + live log panel + JIT dot), Wine server
// control, and about. Includes the live TVLogPanel bound to LogStore.

import SwiftUI
import UIKit

struct TVSettingsScreen: View {
    @EnvironmentObject private var steam: SteamTVLibrary

    var body: some View {
        List {
            accountSection
            displaySection
            performanceSection
            diagnosticsSection
            wineSection
            aboutSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
        .focusSection()
        .background(Color.black.ignoresSafeArea())
        .onAppear { steam.rearmJIT() }
        .confirmationDialog("Sign out of Steam?", isPresented: $signOutPrompt, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { steam.signOut() }
        }
    }

    // MARK: Account

    private var accountSection: some View {
        Section {
            HStack(spacing: TVSpacing.s16) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(steam.accountName ?? "")
                        .font(.headline)
                    Text(steam.signedIn ? "Signed in to Steam" : "Not signed in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                JITDot()
            }
            .padding(.vertical, 4)

            Button {
                steam.loadGames(interactive: true)
            } label: {
                Label("Refresh library", systemImage: "arrow.clockwise")
            }

            Button(role: .destructive) {
                signOutPrompt = true
            } label: {
                Label("Sign out of Steam", systemImage: "person.crop.circle.badge.xmark")
            }
        } header: {
            Text("Account")
        }
    }

    // MARK: Display

    private var displaySection: some View {
        Section {
            Toggle("Show FPS / status HUD over games", isOn: $hud.showHUD)
            Toggle("Monospace HUD font", isOn: $hud.hudMonospace)
            Toggle("Quiet focus effects", isOn: quietFocus)
        } header: {
            Text("Display")
        }
    }

    // MARK: Performance

    private var performanceSection: some View {
        Section {
            Picker("JIT pool", selection: jitPoolSize) {
                Text("256 MB").tag(256)
                Text("512 MB").tag(512)
                Text("1 GB").tag(1024)
            }
            .pickerStyle(.segmented)
            Text("Requested size for the FEX JIT pool. Requires a re-arm to take effect.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                steam.rearmJIT()
            } label: {
                Label("Re-arm JIT pool", systemImage: "bolt.fill")
            }
        } header: {
            Text("Performance")
        } footer: {
            Text("JIT: \(jitStatusText)")
        }
    }

    // MARK: Diagnostics

    private var diagnosticsSection: some View {
        Section {
            Toggle("Verbose logging", isOn: verboseLogging)
                #warning("requires SteamTVLibrary.setVerboseLogging(_:) to take effect at next launch")
            TVLogPanel()
        } header: {
            Text("Diagnostics")
        }
    }

    // MARK: Wine

    private var wineSection: some View {
        Section {
            Button {
                stopWine()
            } label: {
                Label(wineserver_is_running() != 0 ? "Restart Wine server" : "Start Wine server",
                      systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(wineserver_is_running() == 0 && wine_process_is_running() == 0)
        } header: {
            Text("Wine")
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Madeira for tvOS")
                Spacer()
                Text("via Wine + FEX")
                    .foregroundStyle(.secondary)
            }
            if let ip = TVLogServer.localIP() {
                Button {
                    logServerCopy = ip
                } label: {
                    Label("Logs: http://\(ip):\(TVLogServer.port.rawValue)/all",
                          systemImage: "network")
                }
                .contextMenu {
                    Button("Copy address") { logServerCopy = ip }
                }
            }
        } header: {
            Text("About")
        } footer: {
            Text("Sideloaded preview build. Non-commercial use.")
        }
    }

    // MARK: State

    @EnvironmentObject private var hud: TVHUDSettings
    @AppStorage("tv.quietFocus") private var quietFocus = false
    @AppStorage("tv.jitPoolMB") private var jitPoolMB = 512
    @AppStorage("tv.verboseLogging") private var verboseLogging = false
    @State private var logServerCopy: String?
    @State private var signOutPrompt = false

    private var jitPoolSize: Binding<Int> {
        Binding(
            get: { jitPoolMB },
            set: { value in
                jitPoolMB = value
                #warning("requires SteamTVLibrary.setJITPoolSize(_:) to apply the new pool")
            }
        )
    }

    private var jitStatusText: String {
        switch steam.jitStatus {
        case .enabled: return "enabled"
        case .disabled: return "disabled"
        case .unknown: return "unknown"
        }
    }

    private func stopWine() {
        wineserver_stop()
        if wine_process_is_running() != 0 {
            // No forced-kill wire; stopping the server ends the client.
        }
        LogStore.shared.log("[settings] wine server stopped", level: .success)
    }
}

// MARK: - TVLogPanel

/// Live, autoscrolling terminal bound to LogStore.shared.entries. Focus ring
/// around the whole panel; one focusable text; toolbar buttons: clear + copy
/// the network log address.
struct TVLogPanel: View {
    @EnvironmentObject private var logStore: LogStore
    @EnvironmentObject private var steam: SteamTVLibrary

    private let columns = ["Index", "Level", "Message"]

    var body: some View {
        VStack(alignment: .leading, spacing: TVSpacing.s12) {
            HStack {
                Text("Log")
                    .font(.headline)
                Spacer()
                Button {
                    logStore.clear()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                Button {
                    copyNetworkLink()
                } label: {
                    Label("Network", systemImage: "network")
                }
            }
            .focusable(false)

            ScrollView {
                ScrollViewReader { proxy in
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(logStore.entries) { entry in
                            logRow(entry)
                                .id(entry.id)
                        }
                    }
                    .onAppear {
                        if let last = logStore.entries.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                    .onChange(of: logStore.entries.count) {
                        if let last = logStore.entries.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(height: 340)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .topLeading) {
                if logStore.entries.isEmpty {
                    Text("No log entries yet. Launch a game to see Wine traces here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(12)
                }
            }
        }
        .padding(TVSpacing.s12)
        .tvGlassBackdrop(cornerRadius: 18)
        .focusable(true)
    }

    private func logRow(_ entry: LogStore.LogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(logTimestamp(entry.timestamp))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
                .focusable(false)
            Text(levelBadge(entry.level))
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .foregroundStyle(levelColor(entry.level))
                .frame(width: 44, alignment: .leading)
                .focusable(false)
            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .focusable(false)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
    }

    private func logTimestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

    private func levelBadge(_ level: LogStore.LogEntry.Level) -> String {
        switch level {
        case .info: return "INFO"
        case .success: return " OK "
        case .warning: return "WARN"
        case .error: return "ERR "
        }
    }

    private func levelColor(_ level: LogStore.LogEntry.Level) -> Color {
        switch level {
        case .info: return .secondary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    private func copyNetworkLink() {
        if let ip = TVLogServer.localIP() {
            UIPasteboard.general.string = "http://\(ip):\(TVLogServer.port.rawValue)/all"
            LogStore.shared.log("[settings] copied log URL to clipboard", level: .success)
        } else {
            LogStore.shared.log("[settings] no LAN IP available", level: .warning)
        }
    }
}