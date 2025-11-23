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
    #if canImport(Sparkle)
    private let updaterController: SPUStandardUpdaterController
    #endif

    override init() {
        #if canImport(Sparkle)
        self.updaterController = SPUStandardUpdaterController(startingUpdater: true,
                                                              updaterDelegate: nil,
                                                              userDriverDelegate: nil)
        // Enable automatic background checks and downloads for future versions
        self.updaterController.updater.automaticallyChecksForUpdates = true
        self.updaterController.updater.automaticallyDownloadsUpdates = true
        #endif
        super.init()
    }

    func checkForUpdates() {
        #if canImport(Sparkle)
        updaterController.checkForUpdates(nil)
        #endif
    }
}
