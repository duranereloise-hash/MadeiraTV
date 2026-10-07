// SPDX-License-Identifier: GPL-3.0-or-later
// Madeira Converter Exception: see LICENSE-EXCEPTION.md
//
// tvOS Library: searchable + filterable adaptive grid of every owned Windows
// game, with All / Installed / Downloading segments.

import SwiftUI

struct LibraryScreen: View {
    @EnvironmentObject private var steam: SteamTVLibrary
    @State private var searchText = ""
    @State private var filter: LibraryFilter = .all
    @State private var selectedAppID: UInt32?

    private enum LibraryFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case installed = "Installed"
        case downloading = "Downloading"
        var id: String { rawValue }
    }

    private var filtered: [SteamAppInfo] {
        var result = steam.games
        switch filter {
        case .all: break
        case .installed: result = result.filter { steam.isInstalled($0) }
        case .downloading: result = result.filter { steam.progress($0.appID) != nil }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .focusSection()

            if steam.loading && steam.games.isEmpty {
                Spacer()
                VStack(spacing: TVSpacing.s16) {
                    ProgressView()
                    Text("Loading library…").font(.headline)
                }
                Spacer()
            } else if filtered.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .navigationDestination(item: $selectedAppID) { appID in
            TVGameDetailView(appID: appID)
        }
        .background(Color.black.ignoresSafeArea())
    }

    private var header: some View {
        VStack(spacing: TVSpacing.s16) {
            HStack(spacing: TVSpacing.s16) {
                Text("Library")
                    .font(.system(size: 36, weight: .bold))
                Spacer()
                Text("\(filtered.count) games")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .focusable(false)
            }
            .padding(.horizontal, TVSpacing.s48)
            .padding(.top, TVSpacing.s24)

            HStack(spacing: TVSpacing.s24) {
                Picker("Filter", selection: $filter) {
                    ForEach(LibraryFilter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 560)

                searchField
                    .frame(width: 420)
            }
            .padding(.horizontal, TVSpacing.s48)
        }
        .focusSection()
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search games", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 220, maximum: 300), spacing: TVSpacing.s24)
            ], spacing: TVSpacing.s32) {
                ForEach(filtered, id: \.appID) { game in
                    TVPosterCard(game: game, onSelect: { selectedAppID = game.appID })
                }
            }
            .padding(.horizontal, TVSpacing.s48)
            .padding(.vertical, TVSpacing.s32)
        }
        .focusSection()
    }

    private var emptyState: some View {
        VStack(spacing: TVSpacing.s20) {
            Image(systemName: searchText.isEmpty ? "shippingbox" : "magnifyingglass")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text(emptyTitle)
                .font(.title2.bold())
            Text(emptyMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !steam.games.isEmpty || steam.error == nil {
                Button("Refresh library") { steam.loadGames(interactive: true) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, TVSpacing.s48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable(false)
    }

    private var emptyTitle: String {
        if searchText.isEmpty && filter != .all {
            return "Nothing here yet"
        }
        return "No games found"
    }

    private var emptyMessage: String {
        if !searchText.isEmpty {
            return "No owned games match “\(searchText)”."
        }
        switch filter {
        case .installed: return "Install a game from the All tab to see it here."
        case .downloading: return "No downloads in progress."
        case .all: return "Refresh the library to pull your owned Steam games."
        }
    }
}