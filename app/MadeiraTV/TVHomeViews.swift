// SPDX-License-Identifier: GPL-3.0-or-later
// Madeira Converter Exception: see LICENSE-EXCEPTION.md
//
// tvOS Home: hero banner for the last-installed / last-played game, a
// "Continue playing" shelf, and a "Recently added" rail. Shared components:
// FocusCard (focus lift + shadow), TVPosterCard, placeholder and progress
// overlay.

import SwiftUI

// MARK: - Spacing tokens

enum TVSpacing {
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s20: CGFloat = 20
    static let s24: CGFloat = 24
    static let s32: CGFloat = 32
    static let s48: CGFloat = 48
}

// MARK: - FocusCard

/// Standard focus interaction: 1.06 scale lift + a deep shadow while focused.
/// Wraps any focusable content and collapses to a transparent no-op when the
/// wrapped view is not focusable.
struct FocusCard<Content: View>: View {
    @Environment(\.isFocused) private var isFocused
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .shadow(color: isFocused ? .black.opacity(0.55) : .clear,
                    radius: isFocused ? 28 : 0, y: isFocused ? 18 : 0)
            .animation(.easeOut(duration: 0.2), value: isFocused)
    }
}

/// Button style used by tvOS-17 tab bar and pill buttons: shows the system
/// focus ring on top of the lift.
struct FocusCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FocusCard {
            configuration.label
                .contentShape(Rectangle())
        }
        .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

// MARK: - Home view model helpers

extension SteamTVLibrary {
    /// Playable owned games that are currently installed on disk.
    var installedGames: [SteamAppInfo] {
        games.filter { isInstalled($0) }
    }

    /// Games that are either installed or actively downloading (for shelves).
    var recentlyAdded: [SteamAppInfo] {
        let base = games.filter { isInstalled($0) || downloads[$0.appID] != nil }
        return Array(base.prefix(12))
    }
}

// MARK: - HomeScreen

struct HomeScreen: View {
    @EnvironmentObject private var steam: SteamTVLibrary
    @State private var selectedAppID: UInt32?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TVSpacing.s32) {
                header
                content
            }
            .padding(.bottom, TVSpacing.s48)
        }
        .focusSection()
        .navigationDestination(item: $selectedAppID) { appID in
            TVGameDetailView(appID: appID)
        }
        .background(Color.black.ignoresSafeArea())
    }

    private var header: some View {
        HStack(spacing: TVSpacing.s16) {
            Text("Steam")
                .font(.system(size: 36, weight: .bold))
            JITDot()
                .focusable(false)
            Spacer()
            Text(steam.accountName ?? "")
                .font(.title3)
                .foregroundStyle(.secondary)
                .focusable(false)
        }
        .padding(.horizontal, TVSpacing.s48)
        .padding(.top, TVSpacing.s24)
        .focusSection()
    }

    @ViewBuilder
    private var content: some View {
        if steam.loading && steam.games.isEmpty {
            VStack(spacing: TVSpacing.s16) {
                ProgressView()
                Text("Loading libraryвЂ¦")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
        } else if steam.games.isEmpty {
            emptyLibrary
        } else {
            heroBanner
            continueShelf
            recentlyAddedRail
        }
    }

    private var emptyLibrary: some View {
        VStack(spacing: TVSpacing.s20) {
            Image(systemName: "shippingbox")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("No games yet")
                .font(.title2.bold())
            Button("Refresh library") { steam.loadGames(interactive: true) }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 120)
    }

    // MARK: Hero banner

    /// Wide banner for the primary (last-played, else first installed) game.
    /// Artwork bleeds to the edges (ignores safe area); the title + actions sit
    /// safely padded on top.
    private var heroBanner: some View {
        Group {
            if let hero = steam.recentlyAdded.first {
                TVHeroBanner(game: hero, onDetails: { selectedAppID = hero.appID })
                    .padding(.horizontal, TVSpacing.s32)
            }
        }
    }

    // MARK: Continue playing

    private var continueShelf: some View {
        let installed = steam.installedGames
        return Group {
            if !installed.isEmpty {
                shelf(title: "Continue playing", items: installed) { game in
                    TVPosterCard(game: game, onSelect: { selectedAppID = game.appID })
                }
            }
        }
    }

    private var recentlyAddedRail: some View {
        let items = steam.recentlyAdded
        return Group {
            if !items.isEmpty {
                shelf(title: "Recently added", items: items) { game in
                    TVPosterCard(game: game, onSelect: { selectedAppID = game.appID })
                }
            }
        }
    }

    private func shelf<Content: View>(title: String, items: [SteamAppInfo], @ViewBuilder card: @escaping (SteamAppInfo) -> Content) -> some View {
        VStack(alignment: .leading, spacing: TVSpacing.s16) {
            Text(title)
                .font(.title2.bold())
                .padding(.horizontal, TVSpacing.s48)
                .focusable(false)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: TVSpacing.s24) {
                    Spacer(minLength: TVSpacing.s48 / 2)
                    ForEach(items, id: \.appID) { game in
                        card(game)
                    }
                    Spacer(minLength: TVSpacing.s48 / 2)
                }
            }
            .focusSection()
        }
    }
}

// MARK: - Hero banner

struct TVHeroBanner: View {
    @EnvironmentObject private var steam: SteamTVLibrary
    let game: SteamAppInfo
    var onDetails: () -> Void = {}

    private var heroURL: URL? { SteamTVLibrary.heroURL(for: game) }

    var body: some View {
        ZStack(alignment: .leading) {
            AsyncImage(url: heroURL) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                case .failure: TVArtworkPlaceholder()
                default: ProgressView()
                }
            }
            .frame(maxWidth: .infinity)
            .ignoresSafeArea()
            .clipped()
            .overlay {
                LinearGradient(colors: [.clear, .black.opacity(0.55)],
                               startPoint: .top, endPoint: .bottom)
            }
            .focusable(false)

            HStack(alignment: .bottom, spacing: TVSpacing.s32) {
                VStack(alignment: .leading, spacing: TVSpacing.s12) {
                    Text(game.name)
                        .font(.system(size: 46, weight: .heavy))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .frame(maxWidth: 700, alignment: .leading)
                    Text(heroSubtitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .focusable(false)

                Spacer(minLength: 24)

                HStack(spacing: TVSpacing.s12) {
                    heroAction
                    Button(action: onDetails) {
                        Label("Details", systemImage: "info.circle")
                    }
                    .buttonStyle(.bordered)
                    
                }
            }
            .padding(.horizontal, TVSpacing.s48)
            .padding(.bottom, TVSpacing.s48)
            .padding(.top, 200)
        }
        .frame(height: 420)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .contentShape(Rectangle())
        .focusSection()
    }

    private var heroSubtitle: String {
        if steam.progress(game.appID) != nil { return "DownloadingвЂ¦" }
        if steam.isInstalled(game) { return "Installed" }
        return "Not installed"
    }

    @ViewBuilder
    private var heroAction: some View {
        if let progress = steam.progress(game.appID) {
            Button { steam.cancelInstall(game.appID) } label: {
                Label(progressText(progress), systemImage: "xmark.circle")
            }
            .buttonStyle(.borderedProminent)
            
        } else if steam.isInstalled(game) {
            Button { steam.launch(game) { _ in } } label: {
                if steam.launchingID == game.appID {
                    HStack { ProgressView(); Text("StartingвЂ¦") }
                } else {
                    Label("Play", systemImage: "play.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            
        } else {
            Button { steam.install(game) } label: {
                Label("Install", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            
        }
    }

    private func progressText(_ p: SteamDownloadProgress) -> String {
        switch p.phase {
        case .preparing: return "ConnectingвЂ¦"
        case .finishing: return "FinalizingвЂ¦"
        case .downloading:
            return "\(Int((p.fraction * 100).rounded()))%"
        }
    }
}

// MARK: - Poster card

/// Standard library card: hero artwork, name, install/progress overlay and a
/// Play/Install/Details context menu. `.buttonStyle(.card)` keeps the focus
/// ring on the artwork.
struct TVPosterCard: View {
    @EnvironmentObject private var steam: SteamTVLibrary
    let game: SteamAppInfo
    var onSelect: () -> Void = {}

    private var heroURL: URL? { SteamTVLibrary.heroURL(for: game) }

    var body: some View {
        FocusCard {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: TVSpacing.s12) {
                    artwork
                    Text(game.name)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(width: 220, alignment: .leading)
                        .foregroundStyle(.primary)
                    statusLine
                        .frame(width: 220, alignment: .leading)
                }
                .padding(TVSpacing.s12)
                .frame(width: 244, alignment: .leading)
                .background(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .buttonStyle(.card)
            .contextMenu {
                contextMenuItems
            }
        }
    }

    private var artwork: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: heroURL) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                case .failure: TVArtworkPlaceholder()
                default: ProgressView()
                }
            }
            .frame(width: 220, height: 124)
            .clipped()

            if steam.progress(game.appID) != nil {
                TVProgressOverlay(progress: steam.progress(game.appID)!)
            }
        }
        .frame(width: 220, height: 124)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .tvGlassBackdrop(cornerRadius: 14)
        .overlay(alignment: .bottomTrailing) {
            JITDot(canFocus: false)
                .padding(8)
                .opacity(steam.jitStatus == .unknown ? 0 : 0.9)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if steam.progress(game.appID) != nil {
            Text("DownloadingвЂ¦")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if steam.isInstalled(game) {
            Label("Installed", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("Not installed")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        if steam.progress(game.appID) != nil {
            Button(role: .destructive) { steam.cancelInstall(game.appID) } label: {
                Label("Cancel download", systemImage: "xmark.circle")
            }
        } else if steam.isInstalled(game) {
            Button { steam.launch(game) { _ in } } label: {
                Label("Play", systemImage: "play.fill")
            }
            if !steam.sessionActive {
                Button { onSelect() } label: {
                    Label("Details", systemImage: "info.circle")
                }
            }
        } else {
            Button { steam.install(game) } label: {
                Label("Install", systemImage: "arrow.down.circle")
            }
            Button { onSelect() } label: {
                Label("Details", systemImage: "info.circle")
            }
        }
    }
}

// MARK: - Progress overlay

/// Bottom-leading pill showing live download phase + a LinearProgressView.
struct TVProgressOverlay: View {
    let progress: SteamDownloadProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .monospacedDigit()
            if progress.phase == .preparing {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.8, anchor: .leading)
            } else {
                ProgressView(value: progress.fraction)
                    .tint(.white)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .padding(8)
    }

    private var text: String {
        switch progress.phase {
        case .preparing: return "Connecting to SteamвЂ¦"
        case .finishing: return "FinalizingвЂ¦"
        case .downloading:
            let pct = Int((progress.fraction * 100).rounded())
            if progress.bytesPerSecond > 0 {
                return "\(pct)% В· \(String(format: "%.1f MB/s", progress.bytesPerSecond / 1_048_576))"
            }
            return "\(pct)%"
        }
    }
}

// MARK: - Placeholder + JIT dot

/// Fallback artwork when a library image is missing.
struct TVArtworkPlaceholder: View {
    var body: some View {
        ZStack {
            Color.gray.opacity(0.3)
            Image(systemName: "gamecontroller")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
        }
    }
}

/// Reusable JIT status dot + text used across header, poster and settings.
struct JITDot: View {
    @EnvironmentObject private var steam: SteamTVLibrary
    var canFocus = true

    private var color: Color {
        switch steam.jitStatus {
        case .enabled: return .green
        case .disabled: return .red
        case .unknown: return .gray
        }
    }

    private var label: String {
        switch steam.jitStatus {
        case .enabled: return "JIT OK"
        case .disabled: return "JIT OFF"
        case .unknown: return "JIT вЂ¦"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 13, height: 13)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .focusable(canFocus)
    }
}
