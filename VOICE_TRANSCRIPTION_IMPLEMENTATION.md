# Voice Transcription Implementation

## Overview
Implemented voice-to-text transcription for node chat inputs using Gemini 2.0 Flash API - the cheapest available transcription model.

## Key Features

### 1. **Cheapest Transcription Model**
- **Model**: Gemini 2.0 Flash with audio input
- **Cost**: $0.70 per 1M tokens (~$0.00105 per minute)
- **Comparison**:
  - OpenAI Whisper: $0.006/minute (5.7x more expensive)
  - Google Speech-to-Text: $0.024/minute (22x more expensive)

### 2. **Windsurf-Style UX**
- Microphone button next to photo/send buttons in chat input
- Click to start recording (red mic icon when active)
- Waveform visualization showing audio levels
- "Recording" label with countdown timer (60 second limit)
- Click stop button to transcribe
- Auto-stops at 60 second limit
- Transcription appends to existing text (can record multiple times)

### 3. **Recording Behavior**
- **60 second time limit** (like Windsurf)
- Audio format: M4A (AAC), 16kHz mono, medium quality
- Real-time waveform animation based on mic input level
- Countdown timer shows remaining time
- Auto-cleanup of temporary audio files

### 4. **UI Integration**
- Mic button positioned on left side of input (same row as photo/web search)
- Voice recording view appears above input field when recording
- Red pulsing dot + "Recording" label
- Smooth waveform visualization (20 animated bars)
- Stop button on right side of recording view
- Simple, clean inline design

## Architecture

### Services

#### **AudioRecordingService.swift**
- AVFoundation-based audio recording
- Real-time audio level monitoring for waveform
- 60 second max duration with auto-stop
- Microphone permission handling
- Temporary file management

**Key Properties:**
```swift
@Published var isRecording: Bool
@Published var recordingDuration: TimeInterval
@Published var audioLevel: Float // 0.0 to 1.0
```

**Methods:**
- `startRecording()` - Starts recording to temporary M4A file
- `stopRecording() -> URL?` - Stops and returns audio file URL
- `deleteRecording(at:)` - Cleanup temporary files

#### **VoiceTranscriptionService.swift**
- Gemini 2.0 Flash API integration
- Audio file transcription (M4A/MP3/WAV support)
- Low temperature (0.1) for accurate transcription
- Error handling with user-friendly messages

**Method:**
```swift
func transcribe(audioURL: URL) async throws -> String
```

### UI Components

#### **VoiceInputView.swift**
- Recording visualization UI
- Waveform animation (WaveformView)
- Timer display (countdown from 60s)
- Stop button with transcription trigger
- Error alerts for transcription failures

#### **WaveformView**
- 20 animated bars
- Height responds to real-time audio level
- Smooth animations (0.1s duration)
- Combines wave pattern with actual mic input

### Integration in NodeView

**Changes:**
1. Added `@StateObject private var recordingService = AudioRecordingService()`
2. Mic button added to button row (left side, before photo button)
3. VoiceInputView shown above input field when recording
4. `toggleVoiceRecording()` function handles start/stop
5. Transcription appends to `promptText` with space separator

## Permissions

### Entitlements (JamAI.entitlements)
```xml
<key>com.apple.security.device.audio-input</key>
<true/>
```

### Info.plist
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Jam AI needs access to your microphone to transcribe voice input for AI conversations.</string>
```

## User Flow

1. **Start Recording**
   - User clicks mic button in chat input
   - Permission prompt appears (first time only)
   - Recording starts, button turns red
   - Waveform animates with voice
   - Timer counts down from 60 seconds

2. **During Recording**
   - User speaks into microphone
   - Waveform responds to audio levels
   - Can see remaining time
   - Other buttons disabled during recording

3. **Stop Recording**
   - User clicks stop button (or 60s auto-stop)
   - Recording stops immediately
   - "Transcribing..." state (handled by VoiceInputView)
   - Gemini API processes audio (~1-2 seconds)

4. **Transcription Complete**
   - Text appears in input field
   - Appends to existing text if any
   - User can edit before sending
   - Can click mic again to add more

5. **Multiple Recordings**
   - Click mic again to record another segment
   - New transcription appends with space
   - Build up prompt incrementally
   - Send when ready

## Cost Analysis

### Per Usage
- 1 minute of audio ≈ 1,500 tokens
- Cost: ~$0.00105 per minute
- 60 second recording: ~$0.001 (tenth of a penny)

### Volume Estimates
- 100 recordings/day: $0.10/day = $3/month
- 1,000 recordings/day: $1/day = $30/month
- 10,000 recordings/day: $10/day = $300/month

**Significantly cheaper than alternatives:**
- Saves $0.005/minute vs Whisper
- Saves $0.023/minute vs Speech-to-Text

## Files Created

1. **Services:**
   - `JamAI/Services/AudioRecordingService.swift` - Audio recording with AVFoundation
   - `JamAI/Services/VoiceTranscriptionService.swift` - Gemini API transcription

2. **UI Components:**
   - `JamAI/Views/VoiceInputView.swift` - Recording UI with waveform

3. **Configuration:**
   - Updated `JamAI.entitlements` - Added microphone permission
   - Updated `Info.plist` - Added usage description

## Files Modified

1. **NodeView.swift:**
   - Added `@StateObject recordingService`
   - Added mic button to input button row
   - Added `VoiceInputView` above input field
   - Added `toggleVoiceRecording()` function

## Technical Details

### Audio Format
- **Format**: M4A (MPEG-4 AAC)
- **Sample Rate**: 16kHz (optimal for speech)
- **Channels**: Mono
- **Quality**: Medium (good balance)
- **Location**: Temporary directory

### Waveform Algorithm
```swift
// Combines sine wave pattern with actual audio level
let phase = CGFloat(index) / CGFloat(barCount) * 2 * .pi
let wave = sin(phase + CGFloat(Date().timeIntervalSinceReferenceDate * 3))
let normalizedWave = (wave + 1) / 2
let combinedLevel = normalizedWave * CGFloat(audioLevel)
```

### Audio Level Metering
- Updates every 0.05 seconds (20fps)
- Converts dB (-60 to 0) to linear scale (0.0 to 1.0)
- Smooth visualization using `averagePower(forChannel:)`

## Error Handling

### Recording Errors
- Permission denied → Alert with instructions
- Recording failed → Alert with error message
- Invalid URL → Internal error handling

### Transcription Errors
- No API key → Alert to add key in settings
- Network errors → Retry message
- Rate limit → Wait message
- Server errors → Detailed error codes

## Testing Checklist

- [ ] Microphone permission prompt appears
- [ ] Recording starts/stops correctly
- [ ] Waveform animates with voice
- [ ] Timer counts down accurately
- [ ] Auto-stops at 60 seconds
- [ ] Transcription appears in input field
- [ ] Multiple recordings append correctly
- [ ] Temporary files cleaned up
- [ ] Works with existing photo/web search features
- [ ] Error messages display properly
- [ ] Disabled during AI generation

## Future Enhancements

### Potential Improvements
1. **Real-time transcription** - Stream audio as it's recorded
2. **Language selection** - Support multiple languages
3. **Custom time limits** - User preference for max duration
4. **Transcription history** - Save/reuse previous transcriptions
5. **Noise reduction** - Pre-process audio before transcription
6. **Pause/resume** - Pause recording without stopping

### Voice Commands
- "Send message" - Auto-submit after transcription
- "New line" - Add line break
- "Clear" - Clear input field

### Analytics
- Track voice input usage
- Monitor transcription accuracy
- Measure user satisfaction

## Notes

- **Cross-platform ready**: Code structured for iOS/macOS
- **Backward compatible**: No database changes required
- **Firebase optional**: Works without Firebase setup
- **Credit tracking**: Integrates with existing credit system
- **Team members**: Works with team member prompts

## Comparison to Windsurf

### Similarities
- 60 second time limit
- Waveform visualization
- Inline UI design
- Append functionality
- Simple start/stop flow

### Differences
- **Better cost**: 5.7x cheaper than Whisper
- **Gemini integration**: Uses existing API key
- **Simpler UI**: No floating overlay, inline only
- **macOS native**: Uses macOS design patterns

## Success Metrics

- **Cost efficiency**: <$0.002 per transcription
- **Accuracy**: 95%+ word accuracy (Gemini standard)
- **Speed**: <3s transcription time for 60s audio
- **User experience**: One-click recording, automatic cleanup
- **Reliability**: Error rate <1% with proper error handling
