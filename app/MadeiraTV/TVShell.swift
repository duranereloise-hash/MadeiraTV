// SPDX-License-Identifier: GPL-3.0-or-later
// Madeira Converter Exception: see LICENSE-EXCEPTION.md
//
// tvOS shell: root gate, tab shell, tvOS-17 tab-bar fallback, and the shared
// liquid-glass card. Runs on the Siri Remote: focusable sections, per-area
// focusSection(), Menu button exits an active game session.

import SwiftUI

// MARK: - Environment plumbing

/// Shared, app-wide environment objects injected once at the window root so
/// every tab/sheet/overlay can read the same live instances.
private struct SharedEnvironmentModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .environmentObject(SteamTVLibrary.shared)
            .environmentObject(LogStore.shared)
            .environmentObject(TVHUDSettings.shared)
    }
}

extension View {
    func installSharedEnvironment() -> some View {
        modifier(SharedEnvironmentModifier())
    }
}

/// Small ObservableObject mirroring TVSettings so the HUD toggle reflects
/// live without fighting @AppStorage in one direction. `.shared` is a simple
/// singleton; the didSet observers persist every change back to UserDefaults.
@MainActor
final class TVHUDSettings: ObservableObject {
    static let shared = TVHUDSettings()
    @Published var showHUD: Bool = TVSettings.showHUD {
        didSet { TVSettings.showHUD = showHUD }
    }
    @Published var hudMonospace: Bool = TVSettings.hudMonospace {
        didSet { TVSettings.hudMonospace = hudMonospace }
    }
    private init() {}
}

// MARK: - Root gate

/// Gating / overlay switch.
///
/// 1. sessionActive       -> TVInGameOverlay ignores safe areas so the game's
///                           Metal surface fills the screen, HUD floats on top.
/// 2. !signedIn           -> TVOnboardingSignIn.
/// 3. otherwise           -> TVShell (tab UI).
struct TVRootView: View {
    @EnvironmentObject private var steam: SteamTVLibrary
    @EnvironmentObject private var hud: TVHUDSettings

    var body: some View {
        Group {
            if steam.sessionActive {
                TVInGameOverlay()
                    .ignoresSafeArea()
                    .persistentSystemOverlays(.hidden)
            } else if !steam.signedIn {
                TVOnboardingSignIn()
            } else {
                TVShell()
            }
        }
        .onAppear {
            steam.start()
        }
        .onExitCommand {
            if steam.sessionActive {
                steam.stopGame()
            }
        }
    }
}

/// Full-screen Metal surface + floating HUD shown over a running game. The
/// bare CAMetalLayer (TVMetalSurface) sits at window index 0 below everything;
/// the HUD overlay is translucent on top, non-focusable so the game keeps
/// focus.
struct TVInGameOverlay: View {
    @EnvironmentObject private var steam: SteamTVLibrary
    @EnvironmentObject private var hud: TVHUDSettings

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                if hud.showHUD {
                    TVHUDOverlay()
                        .allowsHitTesting(false)
                }
            }
            .onAppear { TVMetalSurface.shared.show() }
            .onDisappear { TVMetalSurface.shared.hide() }
    }
}

/// Primary menu bar (tvOS 26) split into Home / Library / Settings.
struct TVShell: View {
    @State private var selection: TVTab = .home

    var body: some View {
        Group {
            if #available(tvOS 18.0, *) {
                tabView18
            } else {
                TV17TabBar(selection: $selection)
            }
        }
    }

    @available(tvOS 18.0, *)
    private var tabView18: some View {
        TabView(selection: $selection) {
            NavigationStack {
                HomeScreen()
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(TVTab.home)

            NavigationStack {
                LibraryScreen()
            }
            .tabItem { Label("Library", systemImage: "square.grid.2x2.fill") }
            .tag(TVTab.library)

            NavigationStack {
                TVSettingsScreen()
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(TVTab.settings)
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

/// Home / Library / Settings selection.
enum TVTab: Hashable, CaseIterable {
    case home, library, settings
}

// MARK: - tvOS 17 tab-bar fallback

/// Top-row of focusable buttons (tvOS 17: no native sidebar TabView). Each
/// tab keeps its own NavigationStack so .navigationDestination and focus stay
/// per-section; switching swaps the shown stack.
struct TV17TabBar: View {
    @Binding var selection: TVTab

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ForEach(TVTab.allCases, id: \.self) { tab in
                    Button {
                        selection = tab
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: icon(for: tab))
                                .font(.title3)
                            Text(title(for: tab))
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .frame(minHeight: 56)
                        .foregroundStyle(selection == tab ? Color.accentColor : .primary)
                        .background {
                            if selection == tab {
                                Capsule().fill(Color.accentColor.opacity(0.18))
                            }
                        }
                    }
                    .buttonStyle(FocusCardButtonStyle())
                }
                Spacer()
            }
            .padding(.horizontal, 48)
            .padding(.top, 16)
            .frame(maxWidth: .infinity)
            .focusSection()

            Group {
                switch selection {
                case .home:
                    NavigationStack { HomeScreen() }
                case .library:
                    NavigationStack { LibraryScreen() }
                case .settings:
                    NavigationStack { TVSettingsScreen() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func title(for tab: TVTab) -> String {
        switch tab {
        case .home: return "Home"
        case .library: return "Library"
        case .settings: return "Settings"
        }
    }

    private func icon(for tab: TVTab) -> String {
        switch tab {
        case .home: return "house.fill"
        case .library: return "square.grid.2x2.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

// MARK: - TVGlassCard

/// The canonical surface of the app: tvOS 26 uses the native `.glassEffect`,
/// older boxes fall back to the existing LiquidGlass approximation. This is a
/// pure surface — combine it with `FocusCard` for focusable, liftable items.
struct TVGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 24
    @ViewBuilder var content: () -> Content

    var body: some View {
        Group {
            if #available(tvOS 26.0, *) {
                content()
                    .glassEffect()
                    .allowsHitTesting(false)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                content()
                    .liquidGlassBackground(cornerRadius: cornerRadius)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

extension View {
    /// Backdrop helper: apply a glass/liquid-glass background inside focusable
    /// cards. Body draws above the glass; optional `tint` mirrors the focus
    /// accent one card at a time.
    func tvGlassBackdrop(cornerRadius: CGFloat = 24, focused: Bool = false) -> some View {
        background {
            if #available(tvOS 26.0, *) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .glassEffect()
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(focused ? Color.accentColor.opacity(0.22) : Color.clear)
            }
        }
        .compositingGroup()
        .shadow(color: focused ? .black.opacity(0.5) : .black.opacity(0.22),
                radius: focused ? 26 : 14, y: focused ? 16 : 8)
    }
}
// MARK: - Onboarding (sign-in gate)

/// Fullscreen sign-in hero. Reuses the original sign-in gate/form; on tvOS 26
/// the glass card shows the QR/account flow in a polished full-screen layout.
struct TVOnboardingSignIn: View {
    var body: some View {
        TVSignInGate()
    }
}

// MARK: - In-game overlay

/// Full-screen Metal surface + floating HUD over a running game. The bare
/// CAMetalLayer sits at window index 0 below everything; the HUD is a
/// translucent, non-focusable overlay so the game keeps focus.
struct TVInGameOverlay: View {
    @EnvironmentObject private var hud: TVHUDSettings

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                if hud.showHUD {
                    TVHUDOverlay()
                        .allowsHitTesting(false)
                }
            }
            .onAppear { TVMetalSurface.shared.show() }
            .onDisappear { TVMetalSurface.shared.hide() }
    }
}
