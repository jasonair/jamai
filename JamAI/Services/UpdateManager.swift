import Foundation
import Combine
#if canImport(Sparkle)
import Sparkle
#endif

protocol UpdateManaging: AnyObject {
    func checkForUpdates()
}

final class SparkleUpdateManager: NSObject, ObservableObject, UpdateManaging {
    let objectWillChange = ObservableObjectPublisher()
    @Published var updateReadyToInstall = false
    
    #if canImport(Sparkle)
    private lazy var updaterController: SPUStandardUpdaterController = {
        let controller = SPUStandardUpdaterController(startingUpdater: true,
                                                      updaterDelegate: self,
                                                      userDriverDelegate: nil)
        controller.updater.automaticallyChecksForUpdates = true
        controller.updater.automaticallyDownloadsUpdates = true
        controller.updater.checkForUpdatesInBackground()
        return controller
    }()
    #endif

    override init() {
        super.init()
        #if canImport(Sparkle)
        _ = updaterController
        #endif
    }

    func checkForUpdates() {
        #if canImport(Sparkle)
        updaterController.checkForUpdates(nil)
        #endif
    }
}

#if canImport(Sparkle)
extension SparkleUpdateManager: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        // Once Sparkle finishes downloading an update, flip the flag so the UI can show
        // a prominent "Restart to update" button in the top bar.
        DispatchQueue.main.async {
            self.updateReadyToInstall = true
        }
    }
}
#endif
