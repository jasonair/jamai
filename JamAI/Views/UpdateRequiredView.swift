import SwiftUI
import AppKit

struct UpdateRequiredView: View {
    let message: String
    let updateURLString: String?
    
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
                if let url = validUpdateURL {
                    Button("Download Update") {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(40)
    }
    
    private var validUpdateURL: URL? {
        guard let updateURLString = updateURLString else { return nil }
        return URL(string: updateURLString)
    }
}

#Preview {
    UpdateRequiredView(
        message: "A new version of JamAI is available. Please download the latest version to continue.",
        updateURLString: "https://example.com/download"
    )
}
