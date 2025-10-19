//
//  MaintenanceView.swift
//  JamAI
//
//  Maintenance or force update screen
//

import SwiftUI

struct MaintenanceView: View {
    let message: String
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("Under Maintenance")
                .font(.system(size: 28, weight: .bold))
            
            Text(message)
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
    }
}

#Preview {
    MaintenanceView(message: "JamAI is currently undergoing maintenance. Please check back later.")
}
