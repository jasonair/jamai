# ✅ JamAI — Your Next Steps

## 🎯 Immediate Actions (Do This First!)

### 1. Open the Project
```bash
cd /Users/jasonong/Development/jamai
open JamAI.xcodeproj
```
⏱️ **Time: 30 seconds**

---

### 2. Add GRDB Package ⚠️ **CRITICAL**
The app **will not build** without this dependency.

**In Xcode:**
1. Click **File → Add Package Dependencies**
2. Paste this URL: `https://github.com/groue/GRDB.swift`
3. Select version: **6.24.0** (or "Up to Next Major")
4. Click **Add Package**
5. Ensure **GRDB** is checked for **JamAI** target
6. Click **Add Package** again

⏱️ **Time: 2 minutes**

---

### 3. First Build
```bash
# In Xcode, press: Cmd+B
# Or from menu: Product → Build
```

**Expected result:** Build succeeds ✅

If build fails, check:
- [ ] GRDB package is added correctly
- [ ] No syntax errors in files
- [ ] macOS deployment target is 13.0+

⏱️ **Time: 1 minute**

---

### 4. Run the App
```bash
# In Xcode, press: Cmd+R
# Or from menu: Product → Run
```

**Expected result:** Welcome screen appears ✅

⏱️ **Time: 30 seconds**

---

### 5. Get Gemini API Key
1. Visit: **https://aistudio.google.com/app/apikey**
2. Sign in with Google account
3. Click **"Create API Key"**
4. Copy the key (starts with `AIza...`)

⏱️ **Time: 2 minutes**

---

### 6. Configure API Key
1. In JamAI, press **Cmd+,** (Settings)
2. Paste your API key
3. Click **Save API Key**
4. See "Success!" message

⏱️ **Time: 30 seconds**

---

### 7. Create First Project
1. Click **New Project** (or press **Cmd+N**)
2. Choose location (default: `~/Documents/JamAI Projects/`)
3. Name it: **"Test Project"**
4. Click **Save**

**Expected result:** Canvas opens ✅

⏱️ **Time: 1 minute**

---

### 8. Create First Node
1. **Double-click** anywhere on the canvas
2. Node appears
3. Click the **chevron icon** to expand
4. Type in prompt field: **"Explain how a computer works"**
5. Press **Enter** or click **arrow button**

**Expected result:** AI response streams in! ✅

⏱️ **Time: 1 minute**

---

## 🎉 Success Criteria

You've successfully set up JamAI if:
- [x] App builds without errors
- [x] App runs and shows welcome screen
- [x] You can create a new project
- [x] You can create nodes
- [x] AI responds to prompts
- [x] Responses appear in real-time

**Total setup time: ~10 minutes**

---

## 🧪 Quick Feature Test

Try these to verify everything works:

### Test 1: Undo/Redo
1. Create a node
2. Press **Cmd+Z** (node disappears)
3. Press **Cmd+Shift+Z** (node reappears)

✅ **Undo/Redo working**

---

### Test 2: Copy/Paste
1. Select a node (click it)
2. Press **Cmd+C**
3. Press **Cmd+V**
4. New node appears with same content

✅ **Copy/Paste working**

---

### Test 3: Save/Load
1. Create a few nodes
2. Press **Cmd+S** to save
3. Close the app
4. Reopen JamAI
5. Click **Open Project**
6. Select your project

✅ **Persistence working**

---

### Test 4: Export
1. Create some nodes with AI responses
2. Press **Cmd+Shift+E**
3. Choose location
4. Open exported JSON file

✅ **Export working**

---

### Test 5: Light/Dark Mode
1. Press **Cmd+,** (Settings)
2. Change **Theme** to "Dark"
3. Notice UI changes
4. Change to "Light"
5. Notice UI changes again

✅ **Theming working**

---

## 📚 Learn the App

### Keyboard Shortcuts
```
Cmd+N           New Project
Cmd+O           Open Project
Cmd+S           Save
Cmd+Shift+E     Export JSON
Cmd+Z           Undo
Cmd+Shift+Z     Redo
Cmd+C           Copy Node
Cmd+V           Paste Node
Cmd+,           Settings
```

### Mouse/Trackpad
- **Click** node → Select
- **Double-click** canvas → Create node
- **Drag** node → Move
- **Drag** canvas → Pan
- **Pinch** → Zoom
- **Click chevron** → Expand/Collapse

---

## 🚀 Advanced Features

Once basics work, explore:

### Context Inheritance
1. Create a root node with a prompt
2. Create a child node below it
3. Child inherits conversation history
4. Adjust **K-Turns** in Settings to control context length

### RAG (Document Context)
1. Enable **Include RAG** in Settings
2. Import a text document
3. Ask questions about the document
4. AI uses document content in responses

### Freeze Context
1. Create a node with specific context
2. Click "Freeze Context" (if implemented)
3. All children use exact same context

---

## 🐛 Troubleshooting

### "No such module 'GRDB'"
**Solution:**
1. File → Packages → Resolve Package Versions
2. Clean: Cmd+Shift+K
3. Build: Cmd+B

### "API requests failing"
**Solutions:**
- Check internet connection
- Verify API key in Settings
- Check quota: https://aistudio.google.com/

### "Can't create project"
**Solutions:**
- Check write permissions in save location
- Try saving to Desktop first
- Check Console for errors

### "Slow performance"
**Solutions:**
- Collapse unused nodes
- Reduce zoom level
- Close other apps
- Check Activity Monitor for CPU usage

---

## 📖 Documentation

- **Quick Start**: [QUICKSTART.md](QUICKSTART.md)
- **Full Guide**: [README.md](README.md)
- **Setup**: [SETUP.md](SETUP.md)
- **Features**: [IMPLEMENTATION.md](IMPLEMENTATION.md)
- **Summary**: [PROJECT_SUMMARY.md](PROJECT_SUMMARY.md)

---

## 🎓 Sample Projects to Try

### 1. Research Assistant
- Root: "Research renewable energy"
- Branches: Solar, Wind, Hydro
- Sub-branches: Technology, Cost, Impact

### 2. Story Planning
- Root: "Sci-fi novel outline"
- Branches: Characters, Plot, Setting
- Sub-branches: Details for each

### 3. Learning Path
- Root: "Learn SwiftUI"
- Branches: Views, State, Navigation
- Ask questions in each branch

### 4. Decision Making
- Root: "Should I buy a house or rent?"
- Branches: Financial, Lifestyle, Future
- Compare pros/cons

---

## 🎯 30-Day Challenge

### Week 1: Basics
- [ ] Create 5 different projects
- [ ] Use all keyboard shortcuts
- [ ] Try every menu option
- [ ] Export to JSON and Markdown

### Week 2: AI Mastery
- [ ] Test different prompts
- [ ] Adjust K-turns setting
- [ ] Try complex conversations
- [ ] Use context inheritance

### Week 3: Organization
- [ ] Build a large project (50+ nodes)
- [ ] Organize with titles
- [ ] Use collapsed mode
- [ ] Practice navigation

### Week 4: Advanced
- [ ] Import documents for RAG
- [ ] Test with large text files
- [ ] Optimize for performance
- [ ] Share exported notes

---

## 🔄 Feedback Loop

As you use JamAI:

### What's Working Well?
- Note features you love
- Document your workflows
- Share success stories

### What Could Improve?
- Track bugs or issues
- Suggest new features
- Identify pain points

### Future Enhancements
Based on your needs, consider:
- Node templates
- Search functionality
- Multi-selection
- Custom themes
- iOS companion

---

## 🎊 You're Ready!

✅ **Installation complete**
✅ **First test successful**
✅ **Documentation available**
✅ **Support resources ready**

**Now go build amazing thought maps! 🚀🧠**

---

## 📞 Quick Reference

| Action | How |
|--------|-----|
| Create node | Double-click canvas |
| Expand node | Click chevron |
| Move node | Drag |
| Pan canvas | Drag background |
| Zoom | Pinch or use toolbar |
| Save | Cmd+S |
| Undo | Cmd+Z |
| Settings | Cmd+, |
| New project | Cmd+N |

---

**Happy mapping! 🎨**

*Remember: The canvas is infinite, and so are your ideas.*
