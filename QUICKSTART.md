# JamAI Quick Start Guide

Get JamAI running in 5 minutes.

## ⚡ Fast Track

### 1. Open Project in Xcode
```bash
cd /Users/jasonong/Development/jamai
open JamAI.xcodeproj
```

### 2. Add GRDB Package
1. In Xcode menu: **File → Add Package Dependencies**
2. Paste URL: `https://github.com/groue/GRDB.swift`
3. Select version **6.24.0** or later
4. Click **Add Package**
5. Ensure **GRDB** is added to **JamAI** target

### 3. Build & Run
- Press **Cmd+B** to build
- Press **Cmd+R** to run

### 4. Get Gemini API Key
1. Visit: https://aistudio.google.com/app/apikey
2. Sign in with Google account
3. Click **Create API Key**
4. Copy the key

### 5. Configure JamAI
1. Launch JamAI
2. Press **Cmd+,** (Settings)
3. Paste API key
4. Click **Save API Key**

### 6. Create First Project
1. Click **New Project** or press **Cmd+N**
2. Choose save location
3. Name your project
4. Click **Save**

### 7. Start Creating
- **Double-click canvas** to create a node
- **Click node** to expand
- **Type prompt** and press Enter
- **Watch AI respond** in real-time!

### 8. Add Text Labels
- **Click Text tool** in bottom dock
- **Click canvas** to place text
- **Type your text** (auto-focused)
- **Press Enter** or click away to finish

## 🎯 First 5 Minutes

### Create Your First Thought Map

1. **Create root node**
   - Double-click anywhere on canvas
   - Expand the node (click chevron)
   - Edit title: "Project Planning"
   - Type prompt: "Help me plan a mobile app project"
   - Press Enter

2. **Watch AI respond**
   - Response streams in real-time
   - Title and description auto-generate
   - Collapse node to see summary

3. **Create branches**
   - Double-click near first node
   - Ask follow-up: "What features should it have?"
   - Repeat for different aspects

4. **### Navigate & Annotate
   - **Drag canvas** to pan
   - **Pinch** to zoom
   - **Select node** to highlight
   - **Click Text tool** to add labels
   - **Double-click text** to edit

5. **Save your work**
   - Press **Cmd+S**
   - Auto-saves every 30 seconds
   - Find in: `~/Documents/JamAI Projects/`

## 🔥 Power Features

### Keyboard Shortcuts
```
# Project
Cmd+N           New Project
Cmd+S           Save
Cmd+Z           Undo
Cmd+Shift+Z     Redo
Cmd+C           Copy Node
Cmd+V           Paste Node
Cmd+,           Settings
Cmd+Shift+E     Export JSON

# Tools
ESC             Cancel tool / Deselect
```

### Context Settings
1. Open **Settings** (Cmd+,)
2. Adjust **K-Turns** (how many previous messages to include)
3. Toggle **Include Summaries**
4. Enable **RAG** for document-based context

### Export Options
- **JSON**: Full data export
- **Markdown**: Human-readable notes

## 🐛 Troubleshooting

### "No such module 'GRDB'"
→ Add GRDB package (see step 2 above)

### "API key not found"
→ Add API key in Settings (Cmd+,)

### "Build failed"
→ Clean build folder: **Product → Clean Build Folder** (Cmd+Shift+K)

### Nodes not appearing
→ Check zoom level (bottom toolbar shows %)
→ Reset zoom: Click **1x** button

## 📖 Learn More

- **Full Documentation**: [README.md](README.md)
- **Setup Guide**: [SETUP.md](SETUP.md)
- **Implementation Details**: [IMPLEMENTATION.md](IMPLEMENTATION.md)

## 🎓 Tutorial: Planning a Vacation

### Step 1: Root Node
```
Title: "Summer Vacation 2025"
Prompt: "I want to plan a 2-week vacation in Europe. 
         Where should I go and what should I budget?"
```

### Step 2: Branch - Destinations
```
Title: "Destination Options"
Prompt: "Which specific cities in Europe would you 
         recommend for first-time visitors?"
```

### Step 3: Branch - Budget
```
Title: "Budget Breakdown"
Prompt: "Create a detailed budget breakdown for a 
         2-week trip to [chosen city]"
```

### Step 4: Branch - Itinerary
```
Title: "Daily Itinerary"
Prompt: "Create a day-by-day itinerary for my trip"
```

Each branch inherits context from its parent!

## 💡 Tips & Tricks

### Organize Your Canvas
- **Vertical layout**: Parent → Child flows down
- **Horizontal layout**: Alternatives side-by-side
- **Color coding**: Use node colors
- **Text labels**: Add notes, titles, section headers

### Working with Text Labels
- **Create**: Click Text tool → Click canvas
- **Edit**: Double-click any text label
- **Format**: Select text to show formatting bar
  - Bold toggle
  - Font size (8-96pt)
  - Font family (Default/Serif/Mono)
  - Color picker
- **Drag**: Click and drag to reposition
- **Delete**: Select and click trash icon

### Context Management
- **Freeze Context**: Lock specific conversation state
- **K-Turns**: Lower = faster, Higher = more context
- **Summaries**: Compress long conversations

### Performance
- **Collapse nodes**: Improves FPS with many nodes
- **Zoom out**: See full project structure
- **Use search**: Find specific nodes quickly

### Collaboration
- **Export Markdown**: Share readable notes
- **Export JSON**: Backup full project
- **.jam files**: Version control with Git

## 🚀 Next Steps

1. ✅ Complete this quick start
2. ✅ Create your first project
3. ✅ Explore settings and customization
4. ✅ Try RAG with documents
5. ✅ Export your thought maps
6. ✅ Read full documentation

## 🆘 Getting Help

- **Issues**: Check IMPLEMENTATION.md
- **Setup**: See SETUP.md
- **Features**: Read README.md

---

**Ready to map your thoughts? Let's go! 🚀**
