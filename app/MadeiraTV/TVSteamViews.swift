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
                ProgressView("Загрузка…")
                    .onAppear { steam.loadGames(interactive: true) }
            }
        }
        .onAppear { steam.start() }
    }
}

// MARK: - Header (title left, account right)

struct TVHeader: View {
    @EnvironmentObject private var steam: SteamTVLibrary
    @State private var showAccount = false
    @State private var showError = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Steam")
                .font(.system(size: 40, weight: .bold))
            Spacer()
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
        .alert("Steam", isPresented: Binding(get: { steam.error != nil }, set: { if !$0 { steam.error = nil } })) {
            Button("ОК", role: .cancel) {}
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
                .padding(10)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            SecureField("Пароль", text: $password)
                .textFieldStyle(.plain)
                .focused($focus, equals: .password)
                .frame(maxWidth: 520)
                .padding(10)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            if let prompt = model.guardPrompt, let type = prompt.codeType {
                TextField("Код Steam Guard", text: $code)
                    .textFieldStyle(.plain)
                    .focused($focus, equals: .code)
                    .frame(maxWidth: 520)
                    .padding(10)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
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
                Label("Обновить библиотеку", systemImage: "arrow.clockwise")
                    .frame(maxWidth: 280)
            }
            .buttonStyle(.borderedProminent)
            Button("Выйти из Steam", role: .destructive) {
                confirmSignOut = true
            }
            .buttonStyle(.bordered)
            .confirmationDialog("Выйти из Steam?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Выйти", role: .destructive) {
                    steam.signOut()
                    dismiss()
                }
            }
            Button("Готово") { dismiss() }
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

    var body: some View {
        Group {
            if steam.loading && steam.games.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Загрузка библиотеки…")
                        .font(.headline)
                }
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

    /// Fixed-size preview, double-clipped so the image never escapes the box.
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
        if steam.progress(game.appID) != nil { return "Загрузка…" }
        if steam.isInstalled(game) { return "Установлена" }
        return "Не установлена"
    }

    @ViewBuilder
    private var actionButton: some View {
        if let progress = steam.progress(game.appID) {
            if progress.phase == .finishing {
                Button("Отмена") { steam.cancelInstall(game.appID) }
                    .buttonStyle(.bordered)
            } else {
                Button("Отменить") { steam.cancelInstall(game.appID) }
                    .buttonStyle(.bordered)
            }
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
                    Label("Играть", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .alert("Запуск", isPresented: $showLaunchError) {
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
        case .preparing: return "Подключение к Steam…"
        case .finishing: return "Завершение…"
        case .downloading:
            let pct = Int((p.fraction * 100).rounded())
            let mbS = p.bytesPerSecond > 0 ? String(format: "%.1f МБ/с", p.bytesPerSecond / 1_048_576) : ""
            return "\(pct)% \(mbS)".trimmingCharacters(in: .whitespaces)
        }
    }
}