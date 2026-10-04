// SPDX-License-Identifier: GPL-3.0-or-later
// Madeira Converter Exception: see LICENSE-EXCEPTION.md
//
// tvOS home: Steam sign-in gate, the owned-game grid, and a session banner.
// Designed for the Siri Remote: focusable cards, QR sign-in default.

import SwiftUI

enum TVHome {
    struct State {
        var signedIn: Bool = false
        var account: String?
        var games: [SteamAppInfo] = []
        var loading: Bool = false
        var error: String?
        var downloads: [UInt32: SteamDownloadProgress] = [:]
        var launching: UInt32?
    }
}

struct TVHomeView: View {
    @EnvironmentObject private var steam: SteamTVLibrary

    var body: some View {
        NavigationStack {
            Group {
                if !steam.signedIn {
                    TVSignInGate()
                } else if steam.accountName != nil {
                    TVGameGrid()
                        .navigationTitle("Steam")
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Menu {
                                    Text(steam.accountName ?? "")
                                    Button("Обновить библиотеку") { steam.loadGames(interactive: true) }
                                    Button("Выйти из Steam", role: .destructive) { steam.signOut() }
                                } label: {
                                    Image(systemName: "person.crop.circle")
                                }
                            }
                        }
                } else {
                    ProgressView("Загрузка…")
                        .onAppear { steam.loadGames(interactive: true) }
                }
            }
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
            Text("Madeira для tvOS")
                .font(.largeTitle.bold())
            Text("Играй в свои Steam-игры на Apple TV через Wine + FEX")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Подпишись на свою учётную запись Steam — QR-кодом или паролем. Игры из библиотеки можно будет скачать и запустить прямо на приставке.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 620)
            Button {
                showSignIn = true
            } label: {
                Label("Войти в Steam", systemImage: "qrcode")
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
                        Label("Вы вошли как \(name)", systemImage: "checkmark.seal.fill")
                            .font(.title3.bold())
                        Button("Выйти", role: .destructive) { model.signOut() }
                        Button("Готово") { dismiss() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 40)
                } else {
                    Picker("Способ входа", selection: $method) {
                        Text("QR-код").tag(SteamSignInModel.SignInMethod.qr)
                        Text("Пароль").tag(SteamSignInModel.SignInMethod.password)
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.signedIn ? "Готово" : "Отмена") {
                        if !model.signedIn { model.cancelSignIn() }
                        dismiss()
                    }
                }
            }
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
            Text("Отсканируй QR-код приложением Steam и подтверди вход.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if model.signInBusy && model.qrImage == nil {
                Text("Ждём подтверждения…").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var passwordView: some View {
        VStack(spacing: 18) {
            TextField("Логин Steam", text: $account)
                .textFieldStyle(.plain)
                .focused($focus, equals: .account)
                .frame(maxWidth: 520)
            SecureField("Пароль", text: $password)
                .textFieldStyle(.plain)
                .focused($focus, equals: .password)
                .frame(maxWidth: 520)
            if let prompt = model.guardPrompt, let type = prompt.codeType {
                TextField("Код Steam Guard", text: $code)
                    .textFieldStyle(.plain)
                    .focused($focus, equals: .code)
                    .frame(maxWidth: 520)
                    .onSubmit { model.submitGuardCode(code) }
                Text(prompt.hint.isEmpty ? "Введи код из приложения Steam." : prompt.hint)
                    .font(.callout).foregroundStyle(.secondary)
            }
            Button(model.signInBusy ? "Подождите…" : "Войти") {
                model.signIn(account: account, password: password)
            }
            .buttonStyle(.borderedProminent)
            .disabled(account.isEmpty || password.isEmpty || model.signInBusy)
        }
        .frame(maxWidth: 520)
    }
}

// MARK: - Game grid

struct TVGameGrid: View {
    @EnvironmentObject private var steam: SteamTVLibrary

    private let columns = [GridItem(.adaptive(minimum: 340, maximum: 400), spacing: 32)]

    var body: some View {
        Group {
            if steam.loading && steam.games.isEmpty {
                ProgressView("Загрузка библиотеки…")
            } else if steam.games.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)
                    Text("В библиотеке пока нет игр")
                        .font(.title2.bold())
                    Text("Обнови библиотеку или проверь, что аккаунт владеет Windows-играми.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Обновить") { steam.loadGames(interactive: true) }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 32) {
                        ForEach(steam.games, id: \.appID) { game in
                            TVGameCard(game: game)
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.vertical, 32)
                }
            }
        }
        .onAppear { steam.start() }
    }
}

struct TVGameCard: View {
    @EnvironmentObject private var steam: SteamTVLibrary
    let game: SteamAppInfo
    @State private var launchMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.quaternary)
                    .aspectRatio(1.6, contentMode: .fit)
                if let progress = steam.progress(game.appID) {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: progress.fraction)
                        Text(progressText(progress))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(10)
                }
            }
            Text(game.name)
                .font(.headline)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(steam.isInstalled(game) ? "Установлена" : game.oslist.contains("macos") ? "Windows" : "Загрузить")
                .font(.caption)
                .foregroundStyle(.secondary)
            actionButton
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
        .buttonStyle(.card)
    }

    @ViewBuilder
    private var actionButton: some View {
        if let progress = steam.progress(game.appID), progress.phase != .finishing {
            Button("Отменить") { steam.cancelInstall(game.appID) }
                .buttonStyle(.bordered)
        } else if steam.isInstalled(game) {
            Button {
                steam.launch(game) { message in
                    launchMessage = message
                }
            } label: {
                if steam.launchingID == game.appID {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Label("Играть", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .alert("Запуск", isPresented: Binding(get: { launchMessage != nil }, set: { if !$0 { launchMessage = nil } })) {
                Button("ОК", role: .cancel) {}
            } message: {
                Text(launchMessage ?? "")
            }
        } else {
            Button {
                steam.install(game)
            } label: {
                Label("Установить", systemImage: "arrow.down.circle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func progressText(_ p: SteamDownloadProgress) -> String {
        switch p.phase {
        case .preparing: return "Подготовка…"
        case .finishing: return "Завершение…"
        case .downloading:
            let pct = Int((p.fraction * 100).rounded())
            let mbS = p.bytesPerSecond > 0 ? String(format: "%.1f МБ/с", p.bytesPerSecond / 1_048_576) : ""
            return "\(pct)% \(mbS)".trimmingCharacters(in: .whitespaces)
        }
    }
}