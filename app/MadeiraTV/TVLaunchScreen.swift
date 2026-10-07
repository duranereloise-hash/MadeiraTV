// SPDX-License-Identifier: GPL-3.0-or-later
// Madeira Converter Exception: see LICENSE-EXCEPTION.md
//
// tvOS launch overlay: shown while a game is launching (launchingID set but
// the session not yet active). ProgressView + live stage text from
// steam.diagnostics on a glass card.

import SwiftUI

struct TVLaunchScreen: View {
    @EnvironmentObject private var steam: SteamTVLibrary

    /// The game currently launching, if any.
    private var launchingGame: SteamAppInfo? {
        guard let id = steam.launchingID else { return nil }
        return steam.games.first { $0.appID == id }
    }

    var body: some View {
        Group {
            if steam.launchingID != nil && !steam.sessionActive {
                ZStack {
                    Color.black.opacity(0.88)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                    launchCard
                }
                .transition(.opacity)
            }
        }
    }

    private var launchCard: some View {
        VStack(alignment: .center, spacing: TVSpacing.s24) {
            VStack(spacing: TVSpacing.s12) {
                ProgressView()
                    
                    .tint(.white)
                Text("Launching \(launchingGame?.name ?? "game")вЂ¦")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
            }

            if let stage = steam.diagnostics {
                Text(stage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            JITDot(canFocus: false)
                .padding(.top, 4)
        }
        .padding(40)
        .frame(maxWidth: 640)
        .tvGlassBackdrop(cornerRadius: 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
