//
//  VoiceInputView.swift
//  JamAI
//
//  Voice input UI with waveform visualization
//

import SwiftUI

struct VoiceInputView: View {
    @ObservedObject var recordingService: AudioRecordingService
    @Binding var isTranscribing: Bool
    let onTranscriptionComplete: (String) -> Void
    
    @State private var showError = false
    @State private var errorMessage = ""
    
    private let transcriptionService = VoiceTranscriptionService()
    private let maxDuration: TimeInterval = 60
    
    var body: some View {
        Group {
            if recordingService.isRecording {
                recordingView
            } else if isTranscribing {
                transcribingView
            }
        }
        .alert("Transcription Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private var recordingView: some View {
        HStack(spacing: 12) {
            // Waveform visualization
            WaveformView(audioLevel: recordingService.audioLevel)
                .frame(width: 80, height: 24)
            
            // Recording label and timer
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    
                    Text("Recording")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.red)
                }
                
                Text(formatDuration(recordingService.recordingDuration))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            
            Spacer()
            
            // Stop button
            Button(action: stopAndTranscribe) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Stop recording and transcribe")
            .disabled(isTranscribing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var transcribingView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.7)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Transcribing...")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Text("Converting your voice to text")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
    
    private func stopAndTranscribe() {
        guard let recordingURL = recordingService.stopRecording() else { return }
        
        isTranscribing = true
        
        Task {
            do {
                let transcription = try await transcriptionService.transcribe(audioURL: recordingURL)
                
                // Cleanup audio file
                recordingService.deleteRecording(at: recordingURL)
                
                await MainActor.run {
                    isTranscribing = false
                    if !transcription.isEmpty {
                        onTranscriptionComplete(transcription)
                    }
                }
            } catch {
                // Cleanup audio file even on error
                recordingService.deleteRecording(at: recordingURL)
                
                await MainActor.run {
                    isTranscribing = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let remaining = maxDuration - duration
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Waveform Visualization

struct WaveformView: View {
    let audioLevel: Float
    
    private let barCount = 20
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.accentColor)
                    .frame(width: 2)
                    .frame(height: barHeight(for: index))
                    .animation(.easeInOut(duration: 0.1), value: audioLevel)
            }
        }
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        let minHeight: CGFloat = 4
        let maxHeight: CGFloat = 24
        
        // Create wave pattern with current audio level
        let phase = CGFloat(index) / CGFloat(barCount) * 2 * .pi
        let wave = sin(phase + CGFloat(Date().timeIntervalSinceReferenceDate * 3))
        
        // Combine wave pattern with actual audio level
        let normalizedWave = (wave + 1) / 2 // 0 to 1
        let combinedLevel = normalizedWave * CGFloat(audioLevel)
        
        return minHeight + (maxHeight - minHeight) * combinedLevel
    }
}
