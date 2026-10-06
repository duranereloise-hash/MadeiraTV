// SPDX-License-Identifier: GPL-3.0-or-later
// Madeira Converter Exception: see LICENSE-EXCEPTION.md
//
// tvOS HUD overlay shown on top of the running game: live FPS (from DXMT's
// present counter), uptime, render status, wine/server state and JIT state.
// Mirrors the desktop FPSOverlay but rendered as a SwiftUI overlay so it sits
// over the raw CAMetalLayer host without touching the Metal surface.

import SwiftUI
import Combine
import Darwin

struct TVHUDOverlay: View {
    @EnvironmentObject private var steam: SteamTVLibrary

    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    @State private var lastPresents: UInt64 = 0
    @State private var lastTime: Date = Date()
    @State private var fps: Double = 0
    @State private var totalPresents: UInt64 = 0
    @State private var started: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%.0f FPS", fps))
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .foregroundStyle(fps > 0 ? .green : .white)
                Spacer()
                Text("presents \(totalPresents)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Divider().overlay(.white.opacity(0.2))

            row("Uptime", String(format: "%.0f s", -started.timeIntervalSinceNow))
            if let d = steam.diagnostics { row("Render", d) }
            row("WServer", wsState)
            row(" alive", boolDot(wineserver_is_running() != 0))
            row(" main", boolDot(g_ws_main_entered != 0))
            row(" ready", boolDot(g_ws_in_mainloop != 0))
            row("Wine", boolDot(wine_process_is_running() != 0))
            row("JIT", steam.jitStatus == .enabled ? "enabled" : steam.jitStatus == .disabled ? "disabled" : "unknown")
            row("CPU", cpuInfo)
            row("RAM", ramInfo)
        }
        .font(.system(.subheadline, design: .monospaced))
        .padding(14)
        .frame(minWidth: 300, alignment: .leading)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topLeading) {
            Text("Madeira TV HUD")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
                .padding(.top, 3)
        }
        .padding(16)
        .onReceive(timer) { _ in
            let now = Date()
            let p = madeira_get_present_count()
            let dp = p - lastPresents
            lastPresents = p
            let dt = now.timeIntervalSince(lastTime)
            if dt > 0 { fps = Double(dp) / dt }
            lastTime = now
            totalPresents = p
        }
    }

    func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
            Text(value).lineLimit(1).truncationMode(.tail).layoutPriority(1)
            Spacer(minLength: 0)
        }
    }

    private var wsState: String {
        guard wineserver_is_running() != 0 else { return "dead" }
        if g_ws_in_mainloop != 0 { return "ready" }
        if g_ws_main_entered != 0 { return "initializing" }
        return "thread alive"
    }

    private func boolDot(_ on: Bool) -> String { on ? "● on" : "○ off" }

    private var cpuInfo: String {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        return "\(cores) cores"
    }

    private var ramInfo: String {
        let avail = os_proc_available_memory()
        let availMB = UInt64(avail) / 1_048_576
        return "avail \(availMB) MB"
    }
}