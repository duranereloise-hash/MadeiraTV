// SPDX-License-Identifier: GPL-3.0-or-later
// Madeira Converter Exception: see LICENSE-EXCEPTION.md
//
// tvOS Metal surface for DXMT-rendered Windows apps (ports of the iOS
// MetalHostView). The presenting CAMetalLayer must NOT be a SwiftUI-hosted
// view's backing layer (SwiftUI-hosted layers can route through a snapshot
// path where direct Metal presentations are dropped), so it lives in a raw
// UIView added straight to the window, exactly like the iOS app.

import SwiftUI
import UIKit
import Metal
import QuartzCore

/// Raw window-level host for the presenting CAMetalLayer.
final class TVMetalSurface: UIView {
    /// Process-lifetime singleton: one host, one layer, forever. Registered
    /// with DXMT's swapchain exactly once; only its frame is re-laid out.
    static let shared = TVMetalSurface(frame: CGRect(x: 0, y: 0, width: 1280, height: 720))

    override class var layerClass: AnyClass { CAMetalLayer.self }
    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false   // clicks go through to SwiftUI
        backgroundColor = .black
        metalLayer.device = MTLCreateSystemDefaultDevice()
        if metalLayer.device == nil {
            CrashCatcher.write("[render] FATAL: MTLCreateSystemDefaultDevice() = nil — no Metal device on tvOS")
            NSLog("[render] FATAL: no Metal device")
        } else {
            CrashCatcher.write("[render] Metal device OK: \(metalLayer.device!.name)")
        }
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        // The same MeloNX trick as iOS: if the private display-sync selector
        // exists, disabling it takes our presents out of the display-sync
        // scheduling machinery that can silently drop low-cadence presents.
        let syncSel = NSSelectorFromString("setDisplaySyncEnabled:")
        if metalLayer.responds(to: syncSel) {
            metalLayer.perform(syncSel, with: NSNumber(value: false))
        }
        // Set once so DXMT's swapchain setup never blocks on a zero-size
        // layer. After this, DXMT's setProps is the only drawableSize writer.
        metalLayer.drawableSize = CGSize(width: 1280, height: 720)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Attach fullscreen to the current key window.
    func attachToKeyWindow() {
        let window: UIWindow? =
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow } ??
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first
        guard let window else { return }
        if superview !== window {
            removeFromSuperview()
            // Insert at index 0 so any SwiftUI overlay (HUD, dialogs) drawn on
            // top of the window stays ABOVE the Metal surface; without this the
            // raw CAMetalLayer host obscures the overlay.
            window.insertSubview(self, at: 0)
        }
        frame = window.bounds
    }

    /// Register the layer with the display shim once. Must happen before the
    /// first wine_process_start (first D3D11 swapchain).
    private static var registered = false
    func registerDisplay() {
        guard !Self.registered else { return }
        Self.registered = true
        CrashCatcher.write("[render] registerDisplay: layer=\(String(describing: metalLayer)) dev=\(String(describing: metalLayer.device?.name)) size=\(metalLayer.drawableSize)")
        madeira_display_set_layer(metalLayer)
    }

    /// Remove the surface from the window so the SwiftUI menu is visible again.
    func hide() {
        removeFromSuperview()
    }
}