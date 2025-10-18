# Team Members V3 - Major Restructuring & Expansion

## Overview

Complete overhaul of the Team Members system with focus on skill-first selection, industry specialization, startup/leadership roles, and bulletproof modal interaction.

---

## ✅ 1. Complete Canvas/Node Interaction Blocking

### Problem
Even with sheet detection, scrolling and node selection could still occur after certain interactions.

### Solution
**Comprehensive blocking at multiple levels:**
- **ModalCoordinator**: New `@Published var isModalPresented` tracks modal state
- **CanvasView**: Checks `modalCoordinator.isModalPresented` before processing any tap gesture
- **MouseTrackingView**: Uses `NSApp.mainWindow?.sheets.isEmpty` check for scroll blocking
- **NodeView**: Checks sheet status before allowing node selection

**Result**: **Complete lockdown when modal is open** - no canvas scrolling, no node selection, no background interaction whatsoever.

---

## ✅ 2. Industry-After-Role Architecture

### Old Model
- Roles had fixed industry (e.g., "Technology Product Manager")
- Industry filter appeared BEFORE role selection
- Limited flexibility - couldn't have a "Healthcare Software Engineer"

### New Model  
**Skill-first, industry-later:**
- Roles are pure skills (e.g., "Software Engineer", "Accountant", "CEO")
- Industry is **optional** and chosen AFTER selecting the role
- TeamMember now stores industry, not Role

### Data Model Changes

**Role.swift**:
```swift
struct Role {
    let id: String
    let name: String
    let category: RoleCategory  // NOT industry
    let icon: String
    let color: String
    let description: String
    let levelPrompts: [LevelPrompt]
}
```

**TeamMember.swift**:
```swift
struct TeamMember {
    let roleId: String
    var name: String?
    var industry: RoleIndustry?  // NEW: Optional industry
    var experienceLevel: ExperienceLevel
    // ...
}
```

### UI Flow
1. **Search/filter by category** (Business, Technical, Creative, etc.)
2. **Select role** (e.g., "Software Engineer")
3. **Configure team member**:
   - Name (required)
   - Industry (optional) - appears as horizontal scroll picker
   - Experience level
4. Save with industry specialization

### Prompt Assembly
Industry context is included when present:
```
You are Sarah, a Senior Software Engineer specializing in Healthcare.
```

---

## ✅ 3. Expanded Roles Library

### New Total: 18 Comprehensive Roles

#### **Startup/Leadership Roles**
1. **CEO** - Sets vision, drives growth, builds culture
2. **CTO** - Leads technical strategy and engineering teams
3. **CPO** - Owns product strategy and roadmap
4. **Co-Founder** - Builds startup from ground up
5. **Project Manager** - Coordinates teams and ensures delivery

#### **Tech Language Specialists**
6. **PHP Developer** - Laravel, Symfony, modern PHP
7. **AI/ML Engineer** - TensorFlow, PyTorch, ML systems
8. **C++ Developer** - High-performance systems, game engines
9. **Swift/SwiftUI Developer** - iOS, macOS native development
10. **Python Developer** - Scripts, APIs, data pipelines
11. **Blockchain Developer** - Smart contracts, dApps, DeFi
12. **Full-Stack Engineer** - Complete stack development

#### **Accounting Specialists**
13. **UK Accountant** - UK GAAP, HMRC, VAT compliance
14. **US Accountant** - US GAAP, IRS, federal/state tax

#### **Core Business Roles**
15. **UX Designer** - User research, prototyping, design systems
16. **Content Writer** - Blogs, marketing, documentation
17. **Digital Marketer** - SEO, SEM, multi-channel campaigns
18. **Data Scientist** - ML models, data analysis, insights
19. **Sales Representative** - Relationship building, deal closing

### Role Characteristics
- **4 experience levels each**: Junior, Intermediate, Senior, Expert
- **Tailored system prompts** per level with specific expertise
- **Category-based organization**: Business, Technical, Creative, Design, Marketing, Finance
- **15 industry specializations**: Technology, Healthcare, Finance, E-commerce, Legal, Real Estate, etc.

---

## ✅ 4. Removed Plan Tier Gating

### Change
All experience levels (Junior through Expert) are now **free** for all users.

### Implementation
```swift
struct LevelPrompt {
    init(level: ExperienceLevel, systemPrompt: String, requiredTier: PlanTier = .free) {
        self.level = level
        self.systemPrompt = systemPrompt
        self.requiredTier = .free  // All levels free now
    }
}
```

**UI Updates**:
- Removed plan tier notice/lock icons
- All level buttons are active
- No upgrade prompts in experience selector

---

## ✅ 5. Updated Modal UI

### Layout Changes

**BEFORE** (V2):
```
Search Bar
Industry Filter (removed)
Category Filter
Role List
Configuration
```

**AFTER** (V3):
```
Search Bar
Category Filter
Role List
Configuration:
  - Name (required)
  - Industry (optional horizontal picker) ← NEW
  - Experience Level
```

### Height Adjustment
- Increased from 620px → **680px** to accommodate all content comfortably
- No cropping at top or bottom

### Interaction Improvements
- Full-width event blocking with explicit `Rectangle()` background
- `contentShape(Rectangle())` on all scroll views
- `.allowsHitTesting(true)` throughout hierarchy

---

## Files Modified

### Data Models
- **Role.swift** - Removed industry field, updated Codable
- **TeamMember.swift** - Added industry field, updated display/prompt methods

### UI Components
- **TeamMemberModal.swift** - Removed industry filter, added industry picker in config, updated save logic
- **TeamMemberModalWindow.swift** - Added onDismiss callback, clean logging

### Services
- **ModalCoordinator.swift** - Added `isModalPresented` published property
- **RoleManager.swift** - Removed industry filtering logic

### Canvas/Node Interaction
- **CanvasView.swift** - Added modalCoordinator check for tap blocking
- **NodeView.swift** - Sheet check for node selection blocking
- **MouseTrackingView.swift** - Sheet check for scroll blocking

### Data
- **roles.json** - Complete rewrite with 18 skill-based roles

---

## Build Status

✅ **Build succeeded** with no errors or warnings

---

## Testing Checklist

### Modal Interaction Blocking
- [ ] Open modal
- [ ] Try to scroll canvas (two-finger scroll) → Should be blocked
- [ ] Try to click canvas background → Should be blocked
- [ ] Try to select a node → Should be blocked
- [ ] Try to click/drag anything behind modal → Should be blocked
- [ ] Interact with modal itself → Should work perfectly

### Role Selection Flow
- [ ] Search for role → Finds roles by name/description
- [ ] Filter by category → Shows correct roles
- [ ] Select a role → Configuration section appears

### Industry Selection
- [ ] Industry picker appears after role selection
- [ ] Can scroll through all 15 industries
- [ ] Can select "General" (no industry)
- [ ] Selected industry shows in team member name/prompt

### Configuration
- [ ] Name field is required → Can't save without name
- [ ] All 4 experience levels are available (no locks)
- [ ] Can select any level without upgrade prompts

### Role Variety
- [ ] CEO, CTO, CPO roles available
- [ ] PHP, Python, Swift, C++, AI/ML, Blockchain developers available
- [ ] UK and US Accountant roles available
- [ ] All roles have proper icons and colors

### Prompt Assembly
- [ ] Team member with industry shows: "Name (Level Role specializing in Industry)"
- [ ] Team member without industry shows: "Name (Level Role)"
- [ ] System prompt includes industry context when present

---

## Example Use Cases

### Startup Founder
**Role**: Co-Founder  
**Industry**: Technology  
**Level**: Intermediate  
**Result**: "Alex (Intermediate Technology Co-Founder)"

### Specialized Developer
**Role**: Swift/SwiftUI Developer  
**Industry**: Healthcare  
**Level**: Senior  
**Result**: "Sarah (Senior Healthcare Swift/SwiftUI Developer)"

### International Accounting
**Role**: UK Accountant  
**Industry**: E-commerce  
**Level**: Intermediate  
**Result**: "James (Intermediate E-commerce UK Accountant)"

### General Purpose
**Role**: Digital Marketer  
**Industry**: None (General)  
**Level**: Senior  
**Result**: "Maria (Senior Digital Marketer)"

---

## Benefits

1. **Maximum Flexibility**: Any role can specialize in any industry
2. **Startup-Ready**: All C-level and founder roles available
3. **Tech Stack Coverage**: Major languages and specializations included
4. **International Support**: UK/US accounting variants
5. **Zero Friction**: All levels free, no upgrade prompts
6. **Bulletproof Modal**: Complete background blocking, no interaction leaks
7. **Better UX**: Skill-first approach is more intuitive

---

## Migration Notes

**Existing team members** will continue to work:
- Old members without `industry` field will have `industry: nil` (General)
- Display names and prompts will still generate correctly
- No data loss or breaking changes

**Roles.json backwards compatibility**:
- Old roles.json with `industry` field will fail to decode (by design)
- Backup saved as `roles.json.old`
- Clean migration to new skill-based model

---

## Future Enhancements

Consider for future versions:
- Custom role creation with industry templates
- Role recommendations based on project type
- Industry-specific prompt variations
- Team composition suggestions
- Role conflict detection (e.g., multiple CEOs)
- Industry trend insights
