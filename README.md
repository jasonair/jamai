# JamAI — Visual AI Thinking Canvas

A native macOS SwiftUI app for visual, branching AI thinking powered by Gemini 2.0 Flash.

![Platform](https://img.shields.io/badge/platform-macOS-blue)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## 🎯 Overview

JamAI lets you map ideas as a node-based chat canvas, locally saved as `.jam` files. Ultra-fast, private, and scalable to thousands of nodes with 60 FPS performance.

## ✨ Features

### Core Capabilities
- **Infinite Canvas** — Pan and zoom with Metal-accelerated rendering
- **Branching Conversations** — Create child nodes, link nodes, build thought trees
- **AI-Powered** — Streaming responses from Gemini 2.0 Flash
- **Context Inheritance** — Smart context management with K-turn history
- **Auto-Generation** — AI creates titles and descriptions automatically
- **Foldable Nodes** — Collapsed or expanded cards with internal scrolling

### File Management
- **Native Document Type** — `.jam` files with double-click to open
- **Auto-save** — Every 30 seconds with 3 rotating backups
- **Export** — JSON or Markdown formats
- **Project Bundles** — SQLite database within .jam package

### Advanced Features
- **Undo/Redo** — Full history with Cmd+Z/Cmd+Shift+Z (200 steps max)
- **Copy/Paste** — Duplicate nodes and branches
- **RAG Support** — Optional document ingestion (PDF, TXT, MD)
- **Vector Search** — Accelerate framework for cosine similarity
- **Light/Dark Mode** — Auto-follows system or manual override

## 🚀 Getting Started

### Prerequisites
- macOS 13.0+ (Ventura or later)
- Xcode 15.0+
- Swift 5.9+
- Gemini API Key ([Get one here](https://aistudio.google.com/app/apikey))

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/jamai.git
   cd jamai
   ```

2. **Add Dependencies**
   
   Open the project in Xcode and add the following Swift Package:
   
   - **GRDB.swift** — SQLite toolkit
     - URL: `https://github.com/groue/GRDB.swift`
     - Version: 6.24.0 or later
   
   Go to **File → Add Package Dependencies** and paste the URL above.

3. **Build and Run**
   ```bash
   # Open in Xcode
   open JamAI.xcodeproj
   
   # Or build from command line
   xcodebuild -scheme JamAI -configuration Release
   ```

4. **Add Your API Key**
   - Launch the app
   - Go to **Settings** (Cmd+,)
   - Enter your Gemini API key
   - Click **Save API Key**

## 📖 Usage

### Creating a Project
1. Launch JamAI
2. Click **New Project** or press `Cmd+N`
3. Choose a save location
4. Start creating nodes!

### Working with Nodes
- **Create Node** — Double-click on canvas or click "New Node"
- **Expand/Collapse** — Click chevron icon on node
- **Move Node** — Drag node card
- **Edit Title/Description** — Click to edit inline
- **Submit Prompt** — Type in input field, press Enter or click arrow
- **Create Child** — Drag from node bottom to create linked child

### Keyboard Shortcuts
- `Cmd+N` — New Project
- `Cmd+S` — Save Project
- `Cmd+Shift+E` — Export JSON
- `Cmd+Z` — Undo
- `Cmd+Shift+Z` — Redo
- `Cmd+C` — Copy Node
- `Cmd+V` — Paste Node
- `Cmd+,` — Settings
- `Cmd+R` — Regenerate (when node selected)

### Context Settings
- **K-Turns** — How many conversation turns to include (1-50)
- **Include Summaries** — Use node summaries for context compression
- **Include RAG** — Inject retrieved document context
- **Freeze Context** — Lock exact context payload for node

### RAG (Retrieval Augmented Generation)
1. Enable RAG in Settings
2. Import documents (TXT, MD, PDF, DOCX)
3. Documents are chunked and embedded
4. Top-K chunks injected into prompts automatically

## 🏗️ Architecture

```
JamAI/
├── Models/           # Data structures (Node, Edge, Project)
├── Services/         # API clients and business logic
│   ├── GeminiClient.swift
│   ├── RAGService.swift
│   └── CanvasViewModel.swift
├── Views/            # SwiftUI views
│   ├── CanvasView.swift
│   ├── NodeView.swift
│   ├── EdgeLayer.swift
│   ├── SettingsView.swift
│   └── WelcomeView.swift
├── Storage/          # Database and persistence
│   ├── Database.swift
│   └── DocumentManager.swift
├── Utils/            # Helpers and configuration
│   ├── Config.swift
│   ├── VectorMath.swift
│   ├── KeychainHelper.swift
│   └── UndoManager.swift
└── JamAIApp.swift    # App entry point
```

## 🗄️ Database Schema

**projects**
- id, name, system_prompt
- k_turns, include_summaries, include_rag
- rag_k, rag_max_chars, appearance_mode
- created_at, updated_at

**nodes**
- id, project_id, parent_id, x, y
- title, title_source, description, description_source
- prompt, response, ancestry_json, summary
- system_prompt_snapshot, is_expanded, is_frozen_context
- created_at, updated_at

**edges**
- id, project_id, source_id, target_id, created_at

**rag_documents**
- id, project_id, filename, content, created_at

**rag_chunks**
- id, document_id, content, embedding_json, chunk_index

## ⚡ Performance

### Targets
- 5,000 nodes / 6,000 edges @ 60 FPS (M-series Macs)
- View culling with quadtree indexing
- Layer pooling for edge rendering
- Lazy-mounted text views for large content
- Batch updates with Combine

### Optimization Techniques
- **Metal Acceleration** — Canvas rendering via Metal
- **vDSP** — Vector operations for RAG similarity
- **GRDB** — High-performance SQLite access
- **Lazy Loading** — Only render visible nodes
- **Coalesced Updates** — Batch drag operations

## 🔐 Security & Privacy

- **API Keys** — Stored securely in macOS Keychain
- **Local-First** — All data stored locally in `.jam` files
- **No Telemetry** — No analytics or tracking
- **Private AI** — Direct API calls to Gemini (no proxy)

## 🛠️ Development

### Building from Source
```bash
git clone https://github.com/yourusername/jamai.git
cd jamai
open JamAI.xcodeproj
```

### Running Tests
```bash
xcodebuild test -scheme JamAI -destination 'platform=macOS'
```

### Contributing
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## 📋 Roadmap

### Phase 1 (Current)
- [x] Core canvas with pan/zoom
- [x] Node creation and editing
- [x] Gemini API integration
- [x] Context inheritance
- [x] Undo/Redo
- [x] Copy/Paste
- [x] .jam file persistence
- [x] Light/Dark mode
- [x] Basic RAG support

### Phase 2 (Planned)
- [ ] Multi-selection
- [ ] Advanced RAG with more file types
- [ ] Node search and filtering
- [ ] Templates and presets
- [ ] Collaboration features
- [ ] Plugin system
- [ ] iOS companion app

## 🐛 Known Issues

- PDF and DOCX RAG ingestion not yet implemented
- Large node counts (>10k) may impact performance
- Streaming responses may occasionally timeout

## 📄 License

MIT License - see LICENSE file for details

## 🙏 Acknowledgments

- Built with [SwiftUI](https://developer.apple.com/xcode/swiftui/)
- Database powered by [GRDB.swift](https://github.com/groue/GRDB.swift)
- AI by [Google Gemini](https://ai.google.dev/)
- Icons from [SF Symbols](https://developer.apple.com/sf-symbols/)

## 📧 Contact

Questions? Open an issue or contact [your@email.com](mailto:your@email.com)

---

**Made with ❤️ for visual thinkers**
