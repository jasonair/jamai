import SwiftUI
import AppKit

struct UpdateRequiredView: View {
    let message: String
    let updateURLString: String?
    let updateManager: SparkleUpdateManager
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Update Required")
                .font(.system(size: 28, weight: .bold))
            
            Text(message)
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            
            HStack(spacing: 16) {
                Button("Update with Sparkle") {
                    updateManager.checkForUpdates()
                }
                .buttonStyle(.borderedProminent)
                
                if let url = validUpdateURL {
                    Button("Download from Website") {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.bordered)
                }
                
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(40)
        .onAppear {
            // Kick off a Sparkle check as soon as the forced update screen appears
            updateManager.checkForUpdates()
        }
    }
    
    private var validUpdateURL: URL? {
        guard let updateURLString = updateURLString else { return nil }
        return URL(string: updateURLString)
    }
}

#Preview {
    UpdateRequiredView(
        message: "A new version of JamAI is available. Please download the latest version to continue.",
        updateURLString: "https://example.com/download",
        updateManager: SparkleUpdateManager()
    )
}
