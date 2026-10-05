// SPDX-License-Identifier: GPL-3.0-or-later
// Madeira Converter Exception: see LICENSE-EXCEPTION.md
//
// tvOS home: Steam sign-in gate, the owned-game grid, and an account panel.
// Designed for the Siri Remote: focusable cards, QR sign-in default.
//
// Layout notes:
// - A custom header row (title left, account right) instead of the toolbar:
//   `.toolbar`/`.navigationTitle` is unreliable for focus on tvOS.
// - Cards use a fixed-height preview with a double clip (scaledToFill + frame
//   + clipped + clipShape) so artwork never escapes the rounded box.

import SwiftUI

struct TVHomeView: View {
    @EnvironmentObject private var steam: SteamTVLibrary

    var body: some View {
        Group {
            if !steam.signedIn {
                TVSignInGate()
            } else if steam.accountName != nil {
                VStack(spacing: 0) {
                    TVHeader()
                        .padding(.horizontal, 48)
                        .padding(.top, 24)
                    TVGameGrid()
                }
            } else {
                ProgressView("Loading…")
                    .onAppear { steam.loadGames(interactive: true) }
            }
        }
        .onAppear { steam.start() }
        .overlay {
            if steam.sessionActive && TVSettings.showHUD {
                TVHUDOverlay()
                    .allowsHitTesting(false)
            }
        }
        .onExitCommand {
            if steam.sessionActive {
                steam.stopGame()
            }
        }
    }
}

// MARK: - Header (title left, account + logs right)

struct TVHeader: View {
    @EnvironmentObject private var steam: SteamTVLibrary
    @State private var showAccount = false
    @State private var showLogs = false
    @State private var showError = false
    @State private var showSettings = false

    private var jitDot: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(jitColor)
                .frame(width: 14, height: 14)
            Text(jitLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var jitColor: Color {
        switch steam.jitStatus {
        case .enabled: return .green
        case .disabled: return .red
        case .unknown: return .gray
        }
    }

    private var jitLabel: String {
        switch steam.jitStatus {
        case .enabled: return "JIT OK"
        case .disabled: return "JIT OFF"
        case .unknown: return "JIT …"
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Steam")
                .font(.system(size: 40, weight: .bold))
            jitDot
            Spacer()
            Button {
                showLogs = true
            } label: {
                Image(systemName: "doc.text")
                    .font(.title2)
                    .padding(12)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showLogs) {
                TVLogView()
            }
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .padding(12)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showSettings) {
                TVSettingsView()
            }
            Button {
                showAccount = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title2)
                    Text(steam.accountName ?? "")
                        .font(.title3)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.quaternary.opacity(0.6), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 4) {
                if let diag = steam.diagnostics {
                    Text(diag)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let ip = TVLogServer.localIP() {
                    Text("Logs: http://\(ip):\(TVLogServer.port.rawValue)/all")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(.bottom, 8)
        }
        .alert("Steam", isPresented: Binding(get: { steam.error != nil }, set: { if !$0 { steam.error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(steam.error ?? "")
        }
        .sheet(isPresented: $showAccount) {
            TVAccountSheet()
        }
    }
}

// MARK: - Sign in gate

struct TVSignInGate: View {
    @EnvironmentObject private var steam: SteamTVLibrary
    @State private var showSignIn = false

    var body: some View {
        VStack(spacing: 32) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 84))
                .foregroundStyle(.tint)
            Text("Madeira for tvOS")
                .font(.largeTitle.bold())
            Text("Your Steam games on Apple TV via Wine + FEX")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Sign in with your Steam account — QR code or password. Games can be downloaded and launched right on the box.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 620)
            Button {
                showSignIn = true
            } label: {
                Label("Sign in to Steam", systemImage: "qrcode")
                    .font(.title3.bold())
                    .padding(.horizontal, 44)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .sheet(isPresented: $showSignIn) {
            TVSignInView()
        }
        .onAppear { steam.start() }
    }
}

// MARK: - Sign-in sheet (QR default, password fallback)

struct TVSignInView: View {
    @EnvironmentObject private var steam: SteamTVLibrary
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = SteamSignInModel.shared
    @State private var method: SteamSignInModel.SignInMethod = .qr
    @State private var account = ""
    @State private var password = ""
    @State private var code = ""
    @FocusState private var focus: Field?
    private enum Field { case account, password, code }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let name = model.accountName {
                    VStack(spacing: 12) {
                        Label("Signed in as \(name)", systemImage: "checkmark.seal.fill")
                            .font(.title3.bold())
                        Button("Done") { dismiss() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 40)
                } else {
                    Picker("Method", selection: $method) {
                        Text("QR code").tag(SteamSignInModel.SignInMethod.qr)
                        Text("Password").tag(SteamSignInModel.SignInMethod.password)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 520)

                    if method == .qr { qrView } else { passwordView }

                    if let error = model.signInError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .padding(40)
            .navigationTitle("Steam")
            .onAppear {
                model.refresh()
                if !model.signedIn {
                    if method == .qr { model.beginQR() } else { focus = .account }
                }
            }
            .onDisappear { if !model.signedIn { model.cancelSignIn() } }
            .onChange(of: method) { _, value in
                model.cancelSignIn()
                if value == .qr { model.beginQR() } else { focus = .account }
            }
            .onChange(of: model.accountName) { _, name in
                if name != nil {
                    steam.start()
                    dismiss()
                }
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    if !model.signedIn { model.cancelSignIn() }
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .padding(12)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minWidth: 900, minHeight: 560)
    }

    private var qrView: some View {
        VStack(spacing: 20) {
            if let image = model.qrImage {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 360, height: 360)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                ProgressView()
                    .frame(width: 360, height: 360)
            }
            Text("Scan with the Steam mobile app and approve the sign-in.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var passwordView: some View {
        VStack(spacing: 18) {
            TextField("Steam account name", text: $account)
                .textFieldStyle(.plain)
                .focused($focus, equals: .account)
                .frame(maxWidth: 520)
                .padding(10)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            SecureField("Password", text: $password)
                .textFieldStyle(.plain)
                .focused($focus, equals: .password)
                .frame(maxWidth: 520)
                .padding(10)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            if let prompt = model.guardPrompt, let type = prompt.codeType {
                TextField("Steam Guard code", text: $code)
                    .textFieldStyle(.plain)
                    .focused($focus, equals: .code)
                    .frame(maxWidth: 520)
                    .padding(10)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                    .onSubmit { model.submitGuardCode(code) }
                Text(prompt.hint.isEmpty ? "Enter the code from the Steam app." : prompt.hint)
                    .font(.callout).foregroundStyle(.secondary)
            }
            Button(model.signInBusy ? "Please wait…" : "Sign in") {
                model.signIn(account: account, password: password)
            }
            .buttonStyle(.borderedProminent)
            .disabled(account.isEmpty || password.isEmpty || model.signInBusy)
        }
        .frame(maxWidth: 520)
    }
}

// MARK: - Account

struct TVAccountSheet: View {
    @EnvironmentObject private var steam: SteamTVLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSignOut = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
            Text(steam.accountName ?? "")
                .font(.title2.bold())
            if let error = steam.error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Button {
                steam.loadGames(interactive: true)
            } label: {
                Label("Refresh library", systemImage: "arrow.clockwise")
                    .frame(maxWidth: 280)
            }
            .buttonStyle(.borderedProminent)
            Button("Sign out of Steam", role: .destructive) {
                confirmSignOut = true
            }
            .buttonStyle(.bordered)
            .confirmationDialog("Sign out of Steam?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    steam.signOut()
                    dismiss()
                }
            }
            Button("Done") { dismiss() }
                .buttonStyle(.plain)
        }
        .padding(48)
        .frame(minWidth: 560, minHeight: 440)
    }
}

// MARK: - Game grid

struct TVGameGrid: View {
    @EnvironmentObject private var steam: SteamTVLibrary

    private let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 360), spacing: 28)
    ]

    private var installed: [SteamAppInfo] {
        steam.games.filter { steam.isInstalled($0) }
    }

    private var notInstalled: [SteamAppInfo] {
        steam.games.filter { !steam.isInstalled($0) }
    }

    var body: some View {
        Group {
            if steam.loading && steam.games.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading library…")
                        .font(.headline)
                }
            } else if steam.games.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)
                    Text("No games in the library")
                        .font(.title2.bold())
                    Text("Refresh the library, or check that the account owns Windows games.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Refresh") { steam.loadGames(interactive: true) }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if !installed.isEmpty {
                            Text("Installed")
                                .font(.title2.bold())
                                .padding(.horizontal, 48)
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 24) {
                                    ForEach(installed, id: \.appID) { game in
                                        TVInstalledCard(game: game)
                                    }
                                }
                                .padding(.horizontal, 48)
                            }
                        }
                        Text("Library")
                            .font(.title2.bold())
                            .padding(.horizontal, 48)
                            .padding(.top, installed.isEmpty ? 0 : 8)
                        LazyVGrid(columns: columns, spacing: 32) {
                            ForEach(notInstalled.isEmpty ? steam.games : notInstalled, id: \.appID) { game in
                                TVGameCard(game: game)
                            }
                        }
                        .padding(.horizontal, 48)
                    }
                    .padding(.vertical, 32)
                }
            }
        }
    }
}

/// Compact horizontal card used in the "Installed" carousel.
struct TVInstalledCard: View {
    @EnvironmentObject private var steam: SteamTVLibrary
    let game: SteamAppInfo
    @State private var launchMessage: String?

    private var heroURL: URL? { SteamTVLibrary.heroURL(for: game) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: heroURL) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                case .failure: Color.gray.opacity(0.3)
                default: ProgressView()
                }
            }
            .frame(width: 220, height: 124)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(game.name)
                .font(.subheadline.bold())
                .lineLimit(1)
                .frame(width: 220, alignment: .leading)
            Button {
                steam.launch(game) { message in
                    launchMessage = message
                }
            } label: {
                if steam.launchingID == game.appID {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .alert("Launch", isPresented: Binding(get: { launchMessage != nil }, set: { if !$0 { launchMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(launchMessage ?? "")
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct TVGameCard: View {
    @EnvironmentObject private var steam: SteamTVLibrary
    let game: SteamAppInfo
    @State private var launchMessage: String?
    @State private var showLaunchError = false

    private var heroURL: URL? { SteamTVLibrary.heroURL(for: game) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            artwork
            Text(game.name)
                .font(.headline)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            actionButton
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
    }

    private var artwork: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: heroURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholder
                default:
                    ProgressView()
                }
            }
            .frame(width: 300, height: 168)
            .clipped()

            if let progress = steam.progress(game.appID) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(progressText(progress))
                        .font(.caption)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if progress.phase == .preparing {
                        ProgressView().tint(.white)
                    } else {
                        ProgressView(value: progress.fraction).tint(.white)
                    }
                }
                .padding(10)
                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
                .padding(8)
            }
        }
        .frame(width: 300, height: 168)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var placeholder: some View {
        ZStack {
            Color.gray.opacity(0.3)
            Image(systemName: "gamecontroller")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
        }
        .frame(width: 300, height: 168)
    }

    private var statusText: String {
        if steam.progress(game.appID) != nil { return "Downloading…" }
        if steam.isInstalled(game) { return "Installed" }
        return "Not installed"
    }

    @ViewBuilder
    private var actionButton: some View {
        if let progress = steam.progress(game.appID) {
            Button("Cancel") { steam.cancelInstall(game.appID) }
                .buttonStyle(.bordered)
        } else if steam.isInstalled(game) {
            Button {
                steam.launch(game) { message in
                    launchMessage = message
                    if message != nil { showLaunchError = true }
                }
            } label: {
                if steam.launchingID == game.appID {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .alert("Launch", isPresented: $showLaunchError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(launchMessage ?? "")
            }
        } else {
            Button {
                steam.install(game)
            } label: {
                Label("Install", systemImage: "arrow.down.circle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func progressText(_ p: SteamDownloadProgress) -> String {
        switch p.phase {
        case .preparing: return "Connecting to Steam…"
        case .finishing: return "Finalizing…"
        case .downloading:
            let pct = Int((p.fraction * 100).rounded())
            let mbS = p.bytesPerSecond > 0 ? String(format: "%.1f MB/s", p.bytesPerSecond / 1_048_576) : ""
            return "\(pct)% \(mbS)".trimmingCharacters(in: .whitespaces)
        }
    }
}

// MARK: - Logs

struct TVLogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var files: [URL] {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return [
            base.appendingPathComponent("log.txt"),
            base.appendingPathComponent("madeira-log.txt")
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Logs")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Refresh") { refresh() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { refresh() }
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    private func refresh() {
        var parts: [String] = []
        for url in files {
            if let data = try? String(contentsOf: url, encoding: .utf8), !data.isEmpty {
                parts.append("=== \(url.lastPathComponent) ===")
                parts.append(data)
            }
        }
        text = parts.isEmpty ? "(log is empty — launch a game and come back)" : parts.joined(separator: "\n")
    }
}