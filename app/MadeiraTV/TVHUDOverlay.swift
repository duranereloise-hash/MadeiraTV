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
            row("Wine", wineState)
            row("JIT", steam.jitStatus == .enabled ? "enabled (offset \(-67108864))" : steam.jitStatus == .disabled ? "disabled" : "unknown")
            row("CPU", cpuInfo)
            row("RAM", ramInfo)
        }
        .font(.system(.callout, design: .monospaced))
        .padding(18)
        .frame(minWidth: 340, alignment: .leading)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .topLeading) {
            Text("Madeira TV HUD")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .padding(.leading, 20)
                .padding(.top, 4)
        }
        .padding(24)
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
            Text(label).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
            Text(value).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private var wineState: String {
        let ws = wineserver_is_running() != 0
        let wp = wine_process_is_running() != 0
        switch (ws, wp) {
        case (true, true): return "server+process alive"
        case (true, false): return "server only"
        case (false, true): return "process only (stale!)"
        case (false, false): return "none running"
        }
    }

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