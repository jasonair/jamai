//
//  AudioRecordingService.swift
//  JamAI
//
//  Audio recording service using AVFoundation
//

import Foundation
import AVFoundation
import Combine

@MainActor
class AudioRecordingService: ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0 // 0.0 to 1.0 for waveform visualization
    
    private var audioRecorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var levelTimer: Timer?
    private var recordingStartTime: Date?
    
    // Maximum recording duration (60 seconds like Windsurf)
    private let maxDuration: TimeInterval = 60
    
    // Current recording URL
    private var currentRecordingURL: URL?
    
    init() {
        // Permission will be requested when user starts recording
    }
    
    deinit {
        // Cleanup happens naturally when object deallocates
        // stopRecording() is @MainActor so can't be called from deinit
        recordingTimer?.invalidate()
        levelTimer?.invalidate()
        audioRecorder?.stop()
    }
    
    // MARK: - Permission
    
    func requestMicrophonePermission() async -> Bool {
        #if os(macOS)
        return await AVCaptureDevice.requestAccess(for: .audio)
        #else
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        #endif
    }
    
    // MARK: - Recording Control
    
    func startRecording() async throws {
        guard !isRecording else { return }
        
        // Request microphone permission if needed
        let hasPermission = await requestMicrophonePermission()
        guard hasPermission else {
            throw AudioRecordingError.permissionDenied
        }
        
        // Generate temporary file URL
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "voice_recording_\(UUID().uuidString).m4a"
        currentRecordingURL = tempDir.appendingPathComponent(fileName)
        
        guard let url = currentRecordingURL else {
            throw AudioRecordingError.invalidURL
        }
        
        // Configure audio session (macOS doesn't need this, but keep for cross-platform)
        #if !os(macOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)
        #endif
        
        // Configure recorder settings
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000, // 16kHz is good for speech recognition
            AVNumberOfChannelsKey: 1, // Mono
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        
        // Create and configure recorder
        audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.prepareToRecord()
        
        // Start recording
        guard audioRecorder?.record() == true else {
            throw AudioRecordingError.recordingFailed
        }
        
        isRecording = true
        recordingStartTime = Date()
        recordingDuration = 0
        
        // Start timers
        startTimers()
    }
    
    func stopRecording() -> URL? {
        guard isRecording else { return nil }
        
        audioRecorder?.stop()
        stopTimers()
        
        isRecording = false
        recordingDuration = 0
        audioLevel = 0
        
        let url = currentRecordingURL
        currentRecordingURL = nil
        
        return url
    }
    
    // MARK: - Timers
    
    private func startTimers() {
        // Duration timer (updates every 0.1 seconds)
        recordingTimer = Timer.scheduledTimer(
            timeInterval: 0.1,
            target: self,
            selector: #selector(handleRecordingTimer(_:)),
            userInfo: nil,
            repeats: true
        )
        
        // Audio level timer (updates frequently for smooth waveform)
        levelTimer = Timer.scheduledTimer(
            timeInterval: 0.05,
            target: self,
            selector: #selector(handleLevelTimer(_:)),
            userInfo: nil,
            repeats: true
        )
    }
    
    @objc private func handleRecordingTimer(_ timer: Timer) {
        guard let startTime = recordingStartTime else { return }
        
        recordingDuration = Date().timeIntervalSince(startTime)
        
        // Auto-stop at max duration
        if recordingDuration >= maxDuration {
            _ = stopRecording()
        }
    }
    
    @objc private func handleLevelTimer(_ timer: Timer) {
        updateAudioLevel()
    }
    
    private func stopTimers() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        levelTimer?.invalidate()
        levelTimer = nil
    }
    
    private func updateAudioLevel() {
        guard let recorder = audioRecorder, recorder.isRecording else {
            audioLevel = 0
            return
        }
        
        recorder.updateMeters()
        
        // Get average power for channel 0 (mono)
        // Returns decibels (-160 to 0), normalize to 0.0 to 1.0
        let averagePower = recorder.averagePower(forChannel: 0)
        
        // Convert decibels to linear scale (0.0 to 1.0)
        // -160 dB is silence, 0 dB is max
        let minDb: Float = -60
        let normalizedLevel = max(0, min(1, (averagePower - minDb) / (0 - minDb)))
        
        audioLevel = normalizedLevel
    }
    
    // MARK: - Cleanup
    
    func deleteRecording(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Errors

enum AudioRecordingError: LocalizedError {
    case invalidURL
    case recordingFailed
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Failed to create recording file"
        case .recordingFailed:
            return "Failed to start recording"
        case .permissionDenied:
            return "Microphone permission denied. Please enable in System Settings."
        }
    }
}
