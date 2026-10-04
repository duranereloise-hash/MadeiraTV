// SPDX-License-Identifier: GPL-3.0-or-later
// Madeira Converter Exception: see LICENSE-EXCEPTION.md
//
// tvOS Steam library model: sign-in state, the account's owned games and
// their downloads, and direct Wine launch of an installed game.
//
// Reuses the already-ported Steam primitives (SteamSession/SteamLibraryFetcher/
// DepotDownloader/SteamInstallFiles) instead of the iOS-only SteamOwnedLibrary
// (which couples to Madeira Dock and UIKit).

import SwiftUI
import Combine
import Foundation
import Darwin

@MainActor
final class SteamTVLibrary: ObservableObject {
    static let shared = SteamTVLibrary()

    @Published private(set) var signedIn = false
    @Published private(set) var accountName: String?
    @Published private(set) var games: [SteamAppInfo] = []
    @Published private(set) var loading = false
    @Published private(set) var downloads: [UInt32: SteamDownloadProgress] = [:]
    @Published var error: String?
    @Published private(set) var launchingID: UInt32?

    private let session = SteamSession()
    private lazy var fetcher = SteamLibraryFetcher(session: session)
    private lazy var downloader = DepotDownloader(session: session)

    private var installTask: Task<Void, Never>?
    private var libraryTask: Task<Void, Never>?
    private var started = false
    private var shouldRefresh = false

    /// Base folder for the Wine prefix.
    ///
    /// tvOS: uses Library/Caches, not Documents. Some sideload installs on
    /// tvOS do not materialise the sandbox Documents directory at all
    /// (FileManager returns it but it does not exist and cannot be created —
    /// ENOENT on mkdir '.../Documents/wine'). Library/Caches is always
    /// present and writable on tvOS.
    static var prefix: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("wine", isDirectory: true)
    }
    static var drive: URL { prefix.appendingPathComponent("drive_c", isDirectory: true) }
    static var steamApps: URL { SteamInstallPaths.steamApps(drive: drive) }
    static var steamPath: String { drive.path }

    /// Wide Steam store hero (460×215), same CDN the iOS app uses.
    static func heroURL(for app: SteamAppInfo) -> URL? {
        if let header = app.headerImage, !header.isEmpty {
            return URL(string: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/\(app.appID)/\(header)")
        }
        return URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(app.appID)/library_hero.jpg")
    }

    func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(forName: SteamSignIn.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.signInChanged() }
        }
        refreshSignIn()
    }

    private func refreshSignIn() {
        signedIn = SteamSignIn.isSignedIn
        accountName = SteamSignIn.accountName
        if signedIn {
            loadGames(interactive: true)
        } else {
            games = []; downloads = [:]
        }
    }

    private func signInChanged() {
        if SteamSignIn.isSignedIn != signedIn || SteamSignIn.accountName != accountName {
            refreshSignIn()
        }
    }

    func signOut() {
        installTask?.cancel()
        libraryTask?.cancel()
        session.logoff()
        SteamSignIn.signOut()
        signedIn = false
        accountName = nil
        games = []
        downloads = [:]
        error = nil
        SteamLog.event("[steam-tv] signed out")
    }

    /// Owned Windows games + what is already installed on disk.
    func loadGames(interactive: Bool) {
        guard signedIn else { return }
        libraryTask?.cancel()
        loading = interactive
        libraryTask = Task { @MainActor in
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { try await self.session.ensureConnected() }
                    group.addTask {
                        try await Task.sleep(nanoseconds: 25_000_000_000)  // 25s connect cap
                        throw SteamError.connectionTimeout
                    }
                    try await group.next()
                    group.cancelAll()
                }
                try Task.checkCancellation()
                let apps = try await fetcher.fetchOwnedApps()
                try Task.checkCancellation()
                var result = apps.filter {
                    $0.type.isPlayable && Self.isWindowsApp($0)
                }
                // Keep a stable order by name.
                result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                games = result
                self.error = nil
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled {
                    let errorMessage = SteamSignIn.message(error)
                    self.error = errorMessage
                    SteamLog.event("[steam-tv] library failed reason=\(SteamSignIn.reason(error))")
                }
            }
            loading = false
        }
    }

    /// Whether an app has a Windows depot / can install on tvOS's Wine.
    private static func isWindowsApp(_ app: SteamAppInfo) -> Bool {
        if app.oslist.contains("windows") { return true }
        return app.depots.contains { ($0.oslist.isEmpty || $0.oslist.contains("windows")) }
    }

    // MARK: - Downloads

    /// Creates the Wine prefix (drive_c, dosdevices, registry template) if the
    /// prefix-template.tar.gz resource is present, or at least the drive_c dir.
    private func seedPrefixIfNeeded() {
        let prefix = Self.drive.deletingLastPathComponent().path  // Library/Caches/wine
        // FileManager creates the whole chain (Caches is always present;
        // wine/ and drive_c/ are materialised here) in one call.
        do {
            try FileManager.default.createDirectory(at: Self.drive, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o777])
        } catch {
            // Best effort; seed below may still work if drive_c already exists.
        }
        madeira_seed_prefix_if_needed(prefix)
        // Whatever the template covered, ensure the top-level dirs exist.
        // createDirectory may fail inside Wine's tree when an intermediate
        // component already exists with restrictive mode, so layer POSIX mkdir
        // on top with an explicit 0777, and make the whole tree writable.
        ensureDirectoryExists(Self.drive.path)
        ensureDirectoryExists(Self.steamApps.path)
        makeAllWritable(Self.drive.path)
    }

    /// Recursively chmod the Wine tree so Steam downloads can always be
    /// written: directories 0777, files 0666.
    private func makeAllWritable(_ root: String) {
        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: root)
        _ = chmod(root, 0o777)
        guard let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: nil,
                                             options: [.skipsHiddenFiles]) else { return }
        for case let url as URL in enumerator {
            let path = url.path
            if url.hasDirectoryPath { _ = chmod(path, 0o777) }
            else { _ = chmod(path, 0o666) }
        }
    }

    /// mkdir -p with 0777, tolerant of existing dirs. FileManager first so
    /// top-level sandbox folders (Documents and its ancestors) materialise;
    /// POSIX fallback for paths Foundation refuses inside the Wine tree
    /// (NSCocoaErrorDomain 513).
    private func ensureDirectoryExists(_ path: String) {
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o777])
            _ = chmod(path, 0o777)
            return
        } catch {
            // fall through to sequential mkdir
        }
        let isAbsolute = path.hasPrefix("/")
        let comps = path.split(separator: "/").map(String.init)
        var current = ""
        for comp in comps {
            if comp.isEmpty { continue }
            if current.isEmpty { current = (isAbsolute ? "/" : "") + comp }
            else { current += "/" + comp }
            if current == "/" { continue }
_ = mkdir(current, 0o777)
            _ = chmod(current, 0o777)
        }
    }
    func isInstalled(_ app: SteamAppInfo) -> Bool {
        SteamInstallFiles.sizeOnDisk(appID: Int(app.appID), steamApps: Self.steamApps) != nil
    }

    func install(_ app: SteamAppInfo) {
        guard signedIn else { error = "Sign in to Steam to download games."; return }
        installTask?.cancel()
        downloads[app.appID] = SteamDownloadProgress()
        installTask = Task { @MainActor in
            do {
                // Lay down the Wine prefix first: without drive_c the download
                // folder cannot be created (permission error inside "common").
                seedPrefixIfNeeded()
                // Ensure the Steam library folder exists on disk (POSIX mkdir,
                // tolerant of strict Wine tree permissions).
                ensureDirectoryExists(Self.steamApps.path)
                ensureDirectoryExists(Self.steamApps.appendingPathComponent("common", isDirectory: true).path)
                ensureDirectoryExists(Self.steamApps.appendingPathComponent("downloading", isDirectory: true).path)
                // Connect cap: if Steam does not answer within 25s, stop the
                // endless "Подключение к Steam…" state with a visible error.
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask { try await self.session.ensureConnected() }
                    group.addTask {
                        try await Task.sleep(nanoseconds: 25_000_000_000)
                        throw SteamError.connectionTimeout
                    }
                    try await group.next()
                    group.cancelAll()
                }
                // Pre-create the game's install + journal folders with 0777 so
                // DepotDownloader's own createDirectory calls cannot fail.
                let folderName = SteamInstallFiles.safeFolderName(app.installDir.isEmpty ? "app_\(app.appID)" : app.installDir)
                ensureDirectoryExists(Self.steamApps.appendingPathComponent("common", isDirectory: true).appendingPathComponent(folderName, isDirectory: true).path)
                ensureDirectoryExists(Self.steamApps.appendingPathComponent("downloading", isDirectory: true).appendingPathComponent("\(app.appID)", isDirectory: true).path)
                let url = try await downloader.install(app, steamApps: Self.steamApps, ownedDepots: { try? await self.fetcher.ownedDepotIDs() }) { [weak self] progress in
                    MainActor.assumeIsolated {
                        self?.downloads[app.appID] = progress
                    }
                }
                Self.materializeInstallRecord(app: app)
                downloads[app.appID] = SteamDownloadProgress(phase: .finishing)
                SteamLog.event("[steam-tv] installed app=\(app.appID) to=\(url.path)")
                downloads[app.appID] = nil
            } catch is CancellationError {
                downloads[app.appID] = nil
            } catch {
                downloads[app.appID] = nil
                if !Task.isCancelled {
                    self.error = SteamSignIn.message(error)
                    SteamLog.event("[steam-tv] install failed app=\(app.appID) reason=\(SteamSignIn.reason(error))")
                }
            }
        }
    }

    /// After the raw download the folder exists but Steam has no ACF record;
    /// write a minimal appmanifest so the UI counts the game installed and a
    /// future Valve client run sees it too.
    private static func materializeInstallRecord(app: SteamAppInfo) {
        let record = steamApps.appendingPathComponent("appmanifest_\(app.appID).acf")
        guard !FileManager.default.fileExists(atPath: record.path) else { return }
        let folder = SteamInstallFiles.safeFolderName(app.installDir.isEmpty ? "app_\(app.appID)" : app.installDir)
        let text = """
        "AppState"
        {
            "appid"  "\(app.appID)"
            "Universe"  "1"
            "name"  "\(app.name.replacingOccurrences(of: "\"", with: "'"))"
            "StateFlags"  "4"
            "installdir"  "\(folder)"
            "InstalledDepots"
            {
            }
            "SharedDepots"
            {
            }
            "UserConfig"
            {
            }
            "MountedConfig"
            {
            }
        }

        """
        try? text.write(to: record, atomically: true, encoding: .utf8)
    }

    func cancelInstall(_ appID: UInt32) {
        installTask?.cancel()
        downloads[appID] = nil
    }

    func progress(_ appID: UInt32) -> SteamDownloadProgress? { downloads[appID] }

    // MARK: - Launch

    /// Launches an installed game: finds its .exe in the install folder and
    /// starts it through Wine (wineserver + wine_process with MADEIRA_EXE).
    func launch(_ app: SteamAppInfo, completion: @escaping (String?) -> Void) {
        guard isInstalled(app) else { completion("Game is not installed."); return }
        guard let exe = findExecutable(for: app) else { completion("Could not find the game's executable."); return }

        launchingID = app.appID
        let prefix = Self.drive.deletingLastPathComponent().path  // Documents/wine
        let workdir = workdir(for: app)
        DispatchQueue.global(qos: .userInitiated).async {
            let ws = wineserver_start(prefix)
            if ws != 0 { DispatchQueue.main.async { completion("wineserver failed (\(ws))") }; return }
            Thread.sleep(forTimeInterval: 1.0)
            if wineserver_is_running() == 0 { DispatchQueue.main.async { completion("wineserver is not ready") }; return }
            setenv("MADEIRA_EXE", exe, 1)
            setenv("MADEIRA_WORKDIR", workdir, 1)
            let wp = wine_process_start(prefix)
            SteamLog.event("[steam-tv] launch app=\(app.appID) exe=\(exe)")
            DispatchQueue.main.async {
                completion(wp != 0 ? "Wine process failed (\(wp))" : nil)
            }
        }
    }

    /// `C:\Program Files (x86)\Steam\steamapps\common\<dir>\<exe>` for the
    /// game's launch options (first Windows executable), else any .exe found
    /// in the install folder.
    private func findExecutable(for app: SteamAppInfo) -> String? {
        let folder = SteamInstallFiles.safeFolderName(app.installDir.isEmpty ? "app_\(app.appID)" : app.installDir)
        let common = "C:\\Program Files (x86)\\Steam\\steamapps\\common\\\(folder)"
        let launchWindows = app.launches.first { $0.oslist.isEmpty || $0.oslist.contains("windows") }
        if let exe = launchWindows?.executable, !exe.isEmpty {
            let named = exe.replacingOccurrences(of: "/", with: "\\")
                .replacingOccurrences(of: "\\\\", with: "\\")
                .trimmingCharacters(in: .whitespaces)
            // exe may already be a full path or relative to the install dir.
            if named.contains(":") { return named }
            if named.contains("\\") { return common + "\\" + named }
            return common + "\\" + named
        }
        // Fallback: scan the install folder for the first .exe (non-steam).
        let disk = Self.steamApps.appendingPathComponent("common", isDirectory: true)
            .appendingPathComponent(folder, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: disk,
                                                             includingPropertiesForKeys: nil,
                                                             options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in enumerator {
            if url.lastPathComponent.lowercased().hasSuffix(".exe"),
               !url.lastPathComponent.lowercased().contains("steam") {
                let rel = url.path.replacingOccurrences(of: disk.path + "/", with: "")
                return common + "\\" + rel.replacingOccurrences(of: "/", with: "\\")
            }
            if (url.path.count - disk.path.count) > 4000 { break }
        }
        return nil
    }

    private func workdir(for app: SteamAppInfo) -> String {
        let folder = SteamInstallFiles.safeFolderName(app.installDir.isEmpty ? "app_\(app.appID)" : app.installDir)
        return "C:\\Program Files (x86)\\Steam\\steamapps\\common\\\(folder)"
    }
}