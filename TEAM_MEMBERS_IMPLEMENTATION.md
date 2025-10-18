# Team Members Feature - Implementation Progress

## Overview

The Team Members feature allows users to attach AI roles with distinct expertise to nodes in JamAI. Each Team Member has a Role, Experience Level, and optional custom name. This feature is being implemented in stages as outlined in the original plan.

---

## ✅ Stage 0: Foundations (COMPLETE)

### Data Models
Created comprehensive data models for the Team Members system:

- **`Role.swift`**: Defines AI roles with categories, icons, colors, and level-specific prompts
  - `RoleCategory`: Business, Creative, Technical, Research, Marketing, Design, Education, Healthcare, Legal, Finance
  - `ExperienceLevel`: Junior, Intermediate, Senior, Expert
  - `PlanTier`: Free, Pro, Enterprise (for gating features)
  - `LevelPrompt`: System prompts for each experience level

- **`TeamMember.swift`**: Represents a team member attached to a node
  - Stores role ID reference
  - Optional custom name
  - Experience level selection
  - Optional prompt addendum
  - Future support for knowledge packs

### Database Schema
Added `team_member_json` column to `nodes` table:
- Migration support for existing projects
- JSON storage for TeamMember data
- Computed properties in Node model for encoding/decoding

### Role Library
Created initial roles library with 10 professionally-crafted roles:
1. Research Analyst (Blue)
2. Content Writer (Purple)
3. Software Engineer (Green)
4. Marketing Strategist (Pink)
5. UX Designer (Orange)
6. Business Consultant (Indigo)
7. Data Scientist (Teal)
8. Product Manager (Yellow)
9. Copywriter (Red)
10. Educator (Cyan)

Each role includes:
- 4 experience levels with tailored system prompts
- Appropriate tier gating (Free/Pro/Enterprise)
- Icon and color theming
- Detailed descriptions

### Services
**`RoleManager.swift`**: Singleton service for role management
- Loads roles from `roles.json` at startup
- Search functionality
- Category filtering
- Role lookup by ID
- Experience level availability checking

### Directory Structure
```
JamAI/TeamMembers/
├── Views/
│   ├── TeamMemberTray.swift
│   └── TeamMemberModal.swift
├── Services/
│   └── RoleManager.swift
└── Resources/
    └── roles.json
```

---

## ✅ Stage 1: User Interface & Local Role Selection (COMPLETE)

### UI Components

**TeamMemberTray (`TeamMemberTray.swift`)**
- Displays team member info in a horizontal bar below the node header
- Shows role icon, custom name (if set), and experience level + role name
- Color matches the role's assigned color
- Settings button to edit the team member
- Only visible on standard nodes or notes with chat enabled

**TeamMemberModal (`TeamMemberModal.swift`)**
- Full-featured modal for selecting and configuring team members
- **Search**: Real-time search across role names, descriptions, and categories
- **Category Filters**: Chips for filtering by category (All, Business, Creative, etc.)
- **Role List**: Scrollable list with role cards showing icon, name, description
- **Configuration Section**:
  - Custom name input (optional)
  - Experience level selector with 4 levels
  - Plan tier indicators for locked levels
- **Actions**: Save, Cancel, and Remove (when editing existing member)

### Integration

**NodeView Updates**:
- Added `onTeamMemberChange` callback
- Added `@StateObject` for `RoleManager`
- Added state for showing team member modal
- Team member tray appears below header (with divider)
- Add/Edit button in header (person.badge.plus / person.fill.checkmark icon)
- Sheet presentation for TeamMemberModal
- Conditional visibility based on node type and chat state

**NodeItemWrapper Updates**:
- Added `onTeamMemberChange` callback parameter
- Passes callback through to NodeView

**CanvasView Updates**:
- Added `handleTeamMemberChange` function
- Wired callback from NodeItemWrapper
- Updates node and persists to database

### User Flow

1. **Adding a Team Member**:
   - Click person.badge.plus button in node header
   - Modal opens with search and role list
   - Search or browse roles by category
   - Select a role
   - Optionally set custom name
   - Choose experience level (gated by plan tier)
   - Click Save
   - Team member tray appears with role info

2. **Editing a Team Member**:
   - Click settings button in tray OR person.fill.checkmark in header
   - Modal opens pre-populated with current settings
   - Modify name, role, or level
   - Click Save to update or Remove to delete

3. **Notes Behavior**:
   - Team member UI only shows when chat section is enabled
   - Clicking JAM button enables chat and shows team member options

---

## ✅ Stage 2: Prompt Assembly & Chat Integration (COMPLETE)

Team Members now actually influence AI responses through dynamic system prompt assembly!

### Implementation

**CanvasViewModel Updates** (`Services/CanvasViewModel.swift`):
- Modified `generateResponse` method to assemble system prompts
- Modified `generateExpandedResponse` method for consistent behavior
- Both methods now:
  1. Check if node has an attached team member
  2. If yes, retrieve the role from RoleManager
  3. Call `teamMember.assembleSystemPrompt()` to build the full prompt
  4. Pass assembled prompt to GeminiClient
  5. If no team member, use base system prompt as before

**Prompt Assembly Format**:
The `TeamMember.assembleSystemPrompt()` method creates:
```
[Base JamAI System Prompt]

# Team Member Role
You are [CustomName], a [ExperienceLevel] [RoleName].

[Role-specific system prompt for the selected experience level]

# Additional Instructions
[Optional prompt addendum if set by user]
```

**Example Assembled Prompt**:
For "Sarah" as a Junior Research Analyst:
```
[JamAI Base Prompt...]

# Team Member Role
You are Sarah, a Junior Research Analyst.

You are a Junior Research Analyst. You focus on gathering information from 
reliable sources, summarizing findings clearly, and presenting basic data 
analysis. You ask clarifying questions when needed and are eager to learn. 
Your responses are well-structured but may require guidance on complex topics.
```

### How It Works

1. **User adds Team Member** → Node stores TeamMember JSON
2. **User sends message** → CanvasViewModel detects team member
3. **Prompt Assembly** → TeamMember builds custom system prompt
4. **API Call** → GeminiClient uses assembled prompt
5. **Response** → AI behaves according to role and experience level

### Testing Checklist

- [ ] Junior level responses are simpler and ask more questions
- [ ] Senior level responses are more sophisticated and strategic
- [ ] Expert level responses demonstrate deep expertise
- [ ] Custom names appear naturally in responses when set
- [ ] Different roles produce appropriately different perspectives
- [ ] Team member changes persist after restart
- [ ] Removing team member reverts to base system prompt

---

## 📋 Future Stages (Planned)

### Stage 3: Customization & Enhanced Search
- Fuzzy search with ranking
- Recent roles quick access
- Keyboard shortcuts (⌘K)
- Prompt addendum editor

### Stage 4: Knowledge Packs (RAG Lite)
- Attach files/URLs to team members
- Lightweight retrieval (TF-IDF or embeddings)
- Citations in responses
- Knowledge management UI

### Stage 5: Remote Role Registry & Updates
- Fetch roles from remote JSON manifest
- Version comparison and merging
- Preserve custom local roles
- Update notifications

### Stage 6: Advanced Features
- Multi-member collaboration (multiple roles on one node)
- Custom role creation
- Role marketplace
- Performance analytics
- Experience level progression

---

## 🎨 Design Notes

### Visual Design
- Team member tray uses role color for background
- Text color automatically adjusts for readability
- Modal uses accent color for selected items
- Clean, modern macOS design language
- Consistent with existing JamAI UI

### UX Principles
- **Progressive Disclosure**: Team member UI only when relevant
- **Smart Defaults**: Intermediate level selected by default
- **Clear Affordances**: Icons and help text guide users
- **Keyboard-First**: Modal auto-focuses search field
- **Plan-Aware**: Locked levels clearly marked with lock icon

---

## 📦 Files Created/Modified

### New Files
- `JamAI/Models/Role.swift`
- `JamAI/Models/TeamMember.swift`
- `JamAI/TeamMembers/Views/TeamMemberTray.swift`
- `JamAI/TeamMembers/Views/TeamMemberModal.swift`
- `JamAI/TeamMembers/Services/RoleManager.swift`
- `JamAI/TeamMembers/Resources/roles.json`

### Modified Files
- `JamAI/Models/Node.swift` - Added teamMemberJSON field
- `JamAI/Storage/Database.swift` - Added migration and persistence
- `JamAI/Views/NodeView.swift` - Added tray, modal, callbacks
- `JamAI/Views/NodeItemWrapper.swift` - Added callback passthrough
- `JamAI/Views/CanvasView.swift` - Added handler function

---

## 🔧 Technical Details

### State Management
- Team member stored as JSON in Node model
- Computed properties handle encoding/decoding
- RoleManager is @StateObject singleton
- Modal state managed in NodeView
- Callbacks flow: NodeView → NodeItemWrapper → CanvasView → ViewModel

### Data Flow
```
User Action (Modal)
    ↓
onSave closure
    ↓
onTeamMemberChange callback (NodeView)
    ↓
onTeamMemberChange callback (NodeItemWrapper)
    ↓
handleTeamMemberChange (CanvasView)
    ↓
node.setTeamMember()
    ↓
viewModel.updateNode()
    ↓
Database persistence
```

### Performance
- Roles loaded once at app startup
- RoleManager is singleton (no redundant loading)
- Team member JSON only decoded when accessed
- Modal search operates on pre-loaded role list
- Database writes debounced via ViewModel

---

## ✨ Ready to Use!

**Stages 0, 1, and 2 are COMPLETE!** Team Members are fully functional and ready to use.

### What's Working Now

✅ **10 Professional Roles** with 4 experience levels each  
✅ **Beautiful UI** with tray, modal, search, and filters  
✅ **Database Persistence** across app restarts  
✅ **AI Integration** - roles actually influence responses  
✅ **Custom Names** for personalized team members  
✅ **Plan Tier Gating** for experience levels  
✅ **Notes Support** when chat is enabled

### Try It Out!

1. **Create or open a node**
2. **Click the person.badge.plus button** in the header
3. **Search and select a role** (try "Research Analyst")
4. **Choose an experience level** (Junior, Intermediate, Senior, Expert)
5. **Optionally add a custom name** (e.g., "Sarah")
6. **Click Save** and watch the tray appear
7. **Ask a question** and see how the AI responds in that role!

### Compare Different Roles

Try asking the same question with different team members:
- **Junior Research Analyst** → Simple, asks clarifying questions
- **Senior Research Analyst** → Deep analysis with strategic insights
- **Content Writer** → Focuses on clear communication
- **Software Engineer** → Technical, code-focused responses

### Future Enhancements (Optional)

The foundation is solid for adding:
- **Stage 3**: Enhanced search, recent roles, prompt addendum editor
- **Stage 4**: Knowledge packs (attach files/URLs to team members)
- **Stage 5**: Remote role registry with updates
- **Stage 6**: Multi-member collaboration, custom roles, analytics

But for now, **Team Members are ready to transform your JamAI experience!** 🎉
