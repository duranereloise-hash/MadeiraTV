// SPDX-License-Identifier: GPL-3.0-or-later
// Madeira Converter Exception: see LICENSE-EXCEPTION.md
//
// tvOS game detail: full-width hero, big Play/Install action, metadata, launch
// options and a (guarded) Remove action with confirmation. Pushed from Home and
// Library via .navigationDestination(for: appID).

import SwiftUI

struct TVGameDetailView: View {
    @EnvironmentObject private var steam: SteamTVLibrary
    @Environment(\.dismiss) private var dismiss
    let appID: UInt32

    @State private var launchError: String?
    @State private var showLaunchError = false
    @State private var confirmRemove = false

    private var game: SteamAppInfo? {
        steam.games.first { $0.appID == appID }
    }

    private var heroURL: URL? {
        game.flatMap { SteamTVLibrary.heroURL(for: $0) }
    }

    var body: some View {
        Group {
            if let game {
                detail(for: game)
            } else {
                VStack(spacing: TVSpacing.s16) {
                    ProgressView()
                    Text("Loading game…")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onExitCommand { dismiss() }
        .alert("Launch failed", isPresented: $showLaunchError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(launchError ?? "")
        }
        .confirmationDialog("Remove “\(game?.name ?? "")” from this device?",
                            isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                #warning("requires SteamTVLibrary.remove(appID:)")
                // steam.remove(appID: appID) — model does not expose it yet.
            }
        } message: {
            Text("This frees disk space. You can reinstall it from your library at any time.")
        }
    }

    private func detail(for game: SteamAppInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TVSpacing.s32) {
                hero(game)
                VStack(alignment: .leading, spacing: TVSpacing.s24) {
                    actionRow(game)
                    metadata(game)
                    if !game.launches.isEmpty {
                        launchOptions(game)
                    }
                }
                .padding(.horizontal, TVSpacing.s48)
            }
            .padding(.bottom, TVSpacing.s48)
        }
        .focusSection()
    }

    // MARK: Hero

    private func hero(_ game: SteamAppInfo) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: heroURL) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                case .failure: TVArtworkPlaceholder()
                default: ProgressView()
                }
            }
            .frame(maxWidth: .infinity)
            .ignoresSafeArea(edges: .top)
            .clipped()
            .overlay {
                LinearGradient(colors: [.clear, .black.opacity(0.6)],
                               startPoint: .top, endPoint: .bottom)
            }

            Text(game.name)
                .font(.system(size: 54, weight: .heavy))
                .lineLimit(3)
                .padding(.horizontal, TVSpacing.s48)
                .padding(.bottom, TVSpacing.s32)
                .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(height: 360)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, TVSpacing.s32)
        .padding(.top, TVSpacing.s24)
        .focusSection()
    }

    // MARK: Primary action

    private func actionRow(_ game: SteamAppInfo) -> some View {
        HStack(spacing: TVSpacing.s16) {
            primaryAction(game)
            refreshButton
            removeButton(game)
            Spacer()
        }
    }

    @ViewBuilder
    private func primaryAction(_ game: SteamAppInfo) -> some View {
        if let progress = steam.progress(game.appID) {
            VStack(alignment: .leading, spacing: 8) {
                TVProgressOverlay(progress: progress)
                Button(role: .destructive) {
                    steam.cancelInstall(game.appID)
                } label: {
                    Label("Cancel download", systemImage: "xmark.circle")
                }
            }
        } else if steam.isInstalled(game) {
            Button {
                steam.launch(game) { message in
                    if let message {
                        launchError = message
                        showLaunchError = true
                    }
                }
            } label: {
                if steam.launchingID == game.appID {
                    HStack { ProgressView(); Text("Starting…") }
                } else {
                    Label("Play", systemImage: "play.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } else {
            Button {
                steam.install(game)
            } label: {
                Label("Install", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var refreshButton: some View {
        Button {
            steam.loadGames(interactive: true)
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    @ViewBuilder
    private var removeButton: some View {
        if steam.isInstalled(game) && steam.progress(appID) == nil {
            Button(role: .destructive) {
                confirmRemove = true
            } label: {
                Label("Remove", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    // MARK: Metadata

    private func metadata(_ game: SteamAppInfo) -> some View {
        VStack(alignment: .leading, spacing: TVSpacing.s12) {
            if game.installDir.isEmpty == false {
                metadataRow("Folder", game.installDir)
            }
            if game.depots.isEmpty == false {
                metadataRow("Depots", "\(game.depots.count)")
            }
        }
        .focusable(false)
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TVSpacing.s16) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.callout)
    }

    // MARK: Launch options

    private func launchOptions(_ game: SteamAppInfo) -> some View {
        VStack(alignment: .leading, spacing: TVSpacing.s12) {
            Text("Launch options")
                .font(.title3.bold())
                .focusable(false)
            ForEach(Array(game.launches.enumerated()), id: \.offset) { index, option in
                HStack(spacing: TVSpacing.s12) {
                    Image(systemName: "terminal")
                        .foregroundStyle(.secondary)
                    Text(option.executable)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if !option.oslist.isEmpty {
                        Text(option.oslist)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 8)
            }
            .focusable(false)
        }
        .padding(.top, TVSpacing.s16)
    }
}