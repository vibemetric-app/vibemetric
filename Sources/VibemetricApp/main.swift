// Launcher for the Vibemetric app. The app lives in VibemetricAppKit, so other modules can build on it.
import VibemetricAppKit
#if VIBEMETRIC_PRO
import VibemetricPro
#endif

MainActor.assumeIsolated {
    VibemetricMain.beforeLaunch = { app in
        #if VIBEMETRIC_PRO
        // Official builds include the private Pro module (Pro/); it appears only when the build turns Pro on.
        if AppVariant.proEnabled { Pro.register(app: app) }
        #endif
    }
}
VibemetricMain.main()
