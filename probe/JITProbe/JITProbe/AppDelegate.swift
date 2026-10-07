import UIKit
import Darwin

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // JIT probe runs on a background thread so the UI can render the result.
        DispatchQueue.global(qos: .userInitiated).async {
            JITProbe.run()
        }

        let vc = UIViewController()
        vc.view.backgroundColor = .black
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = vc
        window?.makeKeyAndVisible()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let lbl = UILabel()
            lbl.text = "JITProbe running..."
            lbl.textColor = .white
            lbl.textAlignment = .center
            lbl.numberOfLines = 0
            lbl.frame = vc.view.bounds
            vc.view.addSubview(lbl)
            JITProbe.onUpdate = { text in
                DispatchQueue.main.async {
                    lbl.text = text
                }
            }
        }
        return true
    }
}