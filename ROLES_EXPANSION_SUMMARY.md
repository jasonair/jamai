# Roles Expansion & Industry Removal Summary

## ✅ Completed Changes

### 1. **Roles.json Expansion** (127 total roles)
Added roles to meet requirements (10+ per category):

**Education (10 roles):**
- Math Teacher, Science Teacher, English Teacher, History Teacher
- Homework Tutor, Test Prep Specialist, Online Course Instructor
- College Admissions Counselor, Language Teacher, Special Education Teacher

**Finance (12 roles):**
- Personal Finance Advisor, Startup CFO, Investment Analyst
- Corporate Finance Manager, Bookkeeper, Tax Advisor
- Venture Capital Analyst, Financial Controller, Budget Analyst, Financial Planner
- Plus existing: UK Accountant, US Accountant

**Legal (10 roles):**
- Corporate Lawyer, Startup Lawyer, Intellectual Property Lawyer
- Employment Lawyer, Contract Lawyer, Privacy & Data Protection Lawyer
- Compliance Officer, Litigation Attorney, General Counsel, Real Estate Lawyer

**Design (15 roles):**
- UI Designer, Product Designer, Graphic Designer, Brand Designer
- Motion Designer, Interaction Designer, Design Systems Designer
- Illustrator, Web Designer, UX Writer
- 3D Designer, Animation Designer, UI Prototyper, Accessibility Designer
- Plus existing: UX Designer

**Product (10 roles):**
- Product Manager, Technical Product Manager, Growth Product Manager
- AI Product Manager, Platform Product Manager, Data Product Manager
- Consumer Product Manager, B2B Product Manager
- Product Operations Manager, Product Analyst

**AI (10 roles):**
- Prompt Engineer, LLM Engineer, MLOps Engineer
- Computer Vision Engineer, NLP Engineer, AI Research Scientist
- AI Safety Researcher, AI Ethics Specialist, ML Architect, AI Consultant

**Startup (10 roles):**
- Startup Founder, Venture Builder, Startup Advisor
- Accelerator Mentor, Startup Growth Hacker, Startup Recruiter
- Pitch Deck Designer, Startup Operations Manager
- Early-Stage Investor, Startup Community Builder

**Creative (10 roles):**
- Copywriter, Video Editor, Photographer, Creative Director
- Screenwriter, Podcast Producer, Art Director
- Voice Actor, Music Producer
- Plus existing: Content Writer

**Business (10 roles):**
- Business Analyst, Strategy Consultant, Operations Manager
- Business Development Manager, Customer Success Manager
- Plus existing: CEO, CTO, CPO, Co-Founder, Project Manager

**Technical (10 roles):**
- DevOps Engineer
- Plus existing: PHP Dev, AI/ML Engineer, C++ Dev, Swift Dev, Python Dev
- Blockchain Dev, Full-Stack Engineer, Data Scientist

**Research (10 roles):**
- Trends Researcher, Consumer Insights Researcher
- Plus existing: Research Analyst, Academic Researcher, Market Researcher
- UX Researcher, Competitive Intelligence Analyst, Scientific Researcher
- Policy Researcher, User Researcher

**Marketing (10 roles):**
- Community Manager
- Plus existing: Digital Marketer, SEO Specialist, Content Marketer
- Social Media Manager, Email Marketer, Growth Marketer
- Brand Strategist, Performance Marketer, Product Marketer

**Healthcare (10 NEW roles):**
- Wellness Coach, Mental Health Coach, Fitness Coach
- Nutrition Coach, Sleep Coach, Stress Management Coach
- Mindfulness Coach, Life Coach, Yoga Instructor, Habit Coach
- **Note:** All healthcare roles include disclaimers to consult qualified professionals

### 2. **Removed RoleIndustry Enum**
- ✅ Deleted `RoleIndustry` enum from `Role.swift`
- ✅ Removed `industry` field from `TeamMember.swift`
- ✅ Updated `displayName()` and `assembleSystemPrompt()` methods
- ✅ Removed industry selector UI from `TeamMemberModal.swift`
- ✅ Removed `selectedIndustry` state variable

### 3. **Added Healthcare Category**
- ✅ Added `healthcare = "Healthcare"` to `RoleCategory` enum
- ✅ Removed `other = "Other"` from `RoleCategory` enum

### 4. **Team Members on Project Feature**
- ✅ Added `projectTeamMembers` parameter to `TeamMemberModal`
- ✅ Created `ProjectTeamMemberChip` view component
- ✅ Added "Team on this Project" section in modal UI
- ✅ Updated `ModalCoordinator.showTeamMemberModal()` signature
- ✅ Updated `TeamMemberModalWindow` to pass project team members
- ✅ Added TODO comments for RAG/context feature

### 5. **Files Modified**
- `JamAI/TeamMembers/Resources/roles.json` - Expanded to 127 roles
- `JamAI/Models/Role.swift` - Removed RoleIndustry, added Healthcare category
- `JamAI/Models/TeamMember.swift` - Removed industry field and references
- `JamAI/TeamMembers/Views/TeamMemberModal.swift` - Removed industry UI, added project team section
- `JamAI/Services/ModalCoordinator.swift` - Updated function signature
- `JamAI/Views/TeamMemberModalWindow.swift` - Updated to pass project team members

## 🚧 Remaining Work

### 1. **Update NodeView Call Sites**
The following locations need to pass `projectTeamMembers`:

**File:** `JamAI/Views/NodeView.swift`

**Location 1 (Edit existing member):**
```swift
// Line ~76
modalCoordinator.showTeamMemberModal(
    existingMember: node.teamMember,
    projectTeamMembers: [], // TODO: Get from parent
    onSave: onTeamMemberChange,
    onRemove: { onTeamMemberChange(nil) }
)
```

**Location 2 (Add new member):**
```swift
// Line ~428
modalCoordinator.showTeamMemberModal(
    existingMember: nil,
    projectTeamMembers: [], // TODO: Get from parent
    onSave: onTeamMemberChange,
    onRemove: nil
)
```

### 2. **Implement Project Team Members Collection**
Need to add a function in `CanvasViewModel` or pass through view hierarchy:

```swift
// In CanvasViewModel.swift
func getProjectTeamMembers(excludingNodeId: String? = nil) -> [(nodeName: String, teamMember: TeamMember, role: Role?)] {
    let roleManager = RoleManager.shared
    return nodes
        .filter { node in
            // Exclude current node if specified
            if let excludeId = excludingNodeId, node.id == excludeId {
                return false
            }
            return node.teamMember != nil
        }
        .compactMap { node in
            guard let teamMember = node.teamMember else { return nil }
            let role = roleManager.role(withId: teamMember.roleId)
            return (
                nodeName: node.title.isEmpty ? "Untitled" : node.title,
                teamMember: teamMember,
                role: role
            )
        }
}
```

Then pass this down through:
1. `CanvasView` → `NodeItemWrapper` → `NodeView`
2. Or: Add to `NodeView` as a closure parameter

### 3. **Future: RAG Context Implementation**
When implementing chat context sharing between team members:

**Approach:**
1. Collect conversation histories from all nodes with team members
2. Use vector embeddings to find relevant context
3. Create a context summary before each response
4. Append to system prompt in `TeamMember.assembleSystemPrompt()`

**Suggested Format:**
```swift
// In assembleSystemPrompt()
if !projectContext.isEmpty {
    assembled += "\n\n# Project Context\n"
    assembled += "Other team members on this project:\n"
    for context in projectContext {
        assembled += "- \(context.memberName) from '\(context.nodeName)' discussed: \(context.summary)\n"
    }
}
```

**Files to modify:**
- `CanvasViewModel.swift` - Add context gathering
- `TeamMember.swift` - Accept and use project context
- `GeminiClient.swift` - Potentially add context to requests

## 📊 Final Counts

| Category   | Count | Status |
|------------|-------|--------|
| Business   | 10    | ✅     |
| Creative   | 10    | ✅     |
| Technical  | 10    | ✅     |
| Research   | 10    | ✅     |
| Marketing  | 10    | ✅     |
| Design     | 15    | ✅     |
| Education  | 10    | ✅     |
| Healthcare | 10    | ✅     |
| Legal      | 10    | ✅     |
| Finance    | 12    | ✅     |
| Product    | 10    | ✅     |
| AI         | 10    | ✅     |
| Startup    | 10    | ✅     |
| **TOTAL**  | **127** | ✅     |

## ✨ Healthcare Roles Safety

All healthcare roles include important disclaimers in their system prompts:
- **Medical concerns** → Consult qualified healthcare professionals
- **Mental health** → Seek licensed mental health professionals
- **Fitness** → Get medical clearance before starting programs
- **Nutrition** → Consult registered dietitians
- **Sleep issues** → Consult sleep specialists
- **Chronic stress/anxiety** → Seek healthcare professionals
- **Coaching vs Therapy** → Clear distinction maintained

## 🎯 Next Steps

1. Update `NodeView.swift` call sites with project team members parameter
2. Implement `getProjectTeamMembers()` in `CanvasViewModel`
3. Pass project team members through view hierarchy
4. Test the new "Team on this Project" UI section
5. Plan RAG context feature implementation
6. Update documentation

## 🧪 Testing Checklist

- [ ] Roles load correctly without errors
- [ ] All 13 categories appear in filter
- [ ] Healthcare category shows 10 roles
- [ ] No "Other" category appears
- [ ] Industry selector is removed
- [ ] "Team on this Project" section appears when applicable
- [ ] Project team members display with correct colors and icons
- [ ] Modal functions properly without industry field
- [ ] Existing team members load and save correctly
- [ ] No compilation errors in updated files
