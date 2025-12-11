# YouTube Video Node Implementation

## Overview

YouTube video nodes allow users to embed YouTube videos on the canvas and chat with the video content using **Gemini File Search** (same as PDF nodes).

## Features

- **Paste YouTube URLs** via the context menu or toolbar button
- **Thumbnail preview** with video title display
- **Full connector support** - wire YouTube nodes to chat nodes
- **RAG-based search** - transcript uploaded to Gemini File API for semantic search
- **Multi-video support** - connect multiple YouTube nodes to a single chat
- **Consistent with PDFs** - same architecture and search quality as PDF nodes
- **Auto re-upload** - expired files automatically re-uploaded from cached transcript

## Architecture

### New Files Created

| File | Purpose |
|------|---------|
| `JamAI/Services/YouTubeService.swift` | URL validation, metadata extraction, Gemini video context |
| `JamAI/Views/YouTubeNodeView.swift` | Compact node display with thumbnail |
| `JamAI/Views/YouTubeURLInputView.swift` | URL input dialog |

### Modified Files

| File | Changes |
|------|---------|
| `JamAI/Models/Node.swift` | Added `youtube` NodeType, YouTube fields |
| `JamAI/Storage/Database.swift` | Migration for YouTube columns |
| `JamAI/Services/CanvasViewModel.swift` | `createYouTubeNode()`, `buildAIContext()` YouTube support |
| `JamAI/Views/NodeItemWrapper.swift` | YouTube node rendering case |
| `JamAI/Views/CanvasView.swift` | YouTube input sheet, toolbar button |
| `JamAI/Views/CanvasContextMenu.swift` | YouTube button in context menu |
| `JamAI/Views/ZoomControlsView.swift` | YouTube button in toolbar |

## Node Model

```swift
// YouTube data (for youtube nodes)
var youtubeUrl: String?           // Full YouTube URL
var youtubeVideoId: String?       // Extracted video ID (e.g., "dQw4w9WgXcQ")
var youtubeTitle: String?         // Video title from oEmbed
var youtubeThumbnailUrl: String?  // Thumbnail URL for display
var youtubeTranscript: String?    // Cached transcript text (for re-upload)
var youtubeFileUri: String?       // Gemini File API URI (for RAG)
var youtubeFileId: String?        // Gemini file ID for status/deletion
```

## Database Schema

```sql
-- YouTube columns (migration)
youtube_url TEXT
youtube_video_id TEXT
youtube_title TEXT
youtube_thumbnail_url TEXT
youtube_transcript TEXT      -- Cached transcript for re-upload
youtube_file_uri TEXT        -- Gemini File API URI
youtube_file_id TEXT         -- Gemini file ID
```

## Supported YouTube URL Formats

- `https://www.youtube.com/watch?v=VIDEO_ID`
- `https://youtu.be/VIDEO_ID`
- `https://www.youtube.com/embed/VIDEO_ID`
- `https://www.youtube.com/v/VIDEO_ID`
- `https://www.youtube.com/shorts/VIDEO_ID`

## How It Works

### 1. Node Creation
1. User clicks YouTube button in toolbar/context menu
2. URL input dialog appears (auto-pastes from clipboard if valid)
3. YouTubeService validates URL and extracts video ID
4. Metadata fetched via YouTube oEmbed API (free, no API key)
5. Node created with thumbnail URL and title
6. **Background task**: Fetch transcript and upload to Gemini File API

### 2. Transcript Upload (Background)
After node creation, automatically:
1. Fetch YouTube page HTML
2. Extract captions/timedtext URL from page data
3. Download and parse XML captions
4. Store transcript locally (`youtubeTranscript`)
5. Upload transcript as `.txt` file to Gemini File API
6. Store `youtubeFileUri` and `youtubeFileId` in node

### 3. Context Building (Chat)
When a chat node is wired to YouTube node(s):
1. `buildAIContext()` detects connected YouTube nodes with `youtubeFileUri`
2. `PDFSearchService.buildYouTubeContext()` queries Gemini File Search
3. If file expired (48h), auto re-uploads from cached `youtubeTranscript`
4. Gemini performs semantic search on transcript
5. Relevant context injected into chat prompt

## Cost Model

| Operation | Cost | Notes |
|-----------|------|-------|
| Transcript fetch | FREE | No API costs |
| File upload | ~FREE | Text files are tiny |
| AI query | Standard token cost | Uses Gemini File Search |

**Same as PDF**: Files expire after 48 hours but auto re-upload from cached transcript.

## UI Components

### YouTubeNodeView
- 280×180px compact display
- Thumbnail with play button overlay
- Video title (2 lines max)
- Hover actions: Open in browser, Delete
- Full connector support (all 4 sides)

### YouTubeURLInputView
- URL text field with paste button
- Real-time URL validation
- Auto-paste from clipboard if valid YouTube URL
- Supported formats hint

## Usage Flow

1. **Add Video**: Right-click canvas → "Add YouTube Video" OR click toolbar button
2. **Paste URL**: Enter YouTube URL in dialog
3. **Connect**: Wire YouTube node to a chat node
4. **Chat**: Ask questions about the video content

## Example Queries

- "What are the main points discussed in this video?"
- "Summarize the key takeaways"
- "What does the speaker say about [topic]?"
- "What advice is given about [subject]?"
- "List the steps mentioned for [process]"

## Limitations

1. **Captions required**: Videos without captions/subtitles cannot be analyzed
2. **Text-only**: Visual content not captured (only spoken content via captions)
3. **Private videos**: Cannot access private or age-restricted videos
4. **File expiration**: Gemini files expire after 48 hours (auto re-uploaded)

## Future Enhancements

- [ ] Timestamp linking in responses
- [ ] Video preview playback in node
- [ ] YouTube playlist support
- [ ] Gemini native video upload (for visual analysis)
- [ ] Progress indicator during transcript upload
