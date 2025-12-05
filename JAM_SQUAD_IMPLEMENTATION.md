# Jam Squad - Multi-Agent Orchestration Feature

## Overview

Jam Squad is a multi-agent orchestration system that allows a "Master Node" to analyze complex problems, spawn specialist delegate nodes, coordinate parallel expert consultations, and synthesize responses into a unified answer.

## User Flow

### 1. User Triggers Jam Squad
- User types a complex question in any standard node
- User clicks the **"Squad"** button in the input area (next to image upload)
- The button is only enabled when there's text in the prompt field

### 2. AI Analyzes and Proposes Roles
- The orchestrator AI analyzes the question
- Proposes 2-4 specialist roles from the roles library
- Each role includes:
  - Role name and justification
  - A tailored question specific to that specialist's expertise

### 3. Nodes Spawn (Org Chart Layout)
- Delegate nodes are created below the master node
- Each node is assigned the appropriate Team Member role
- Bidirectional edges connect master ↔ delegates:
  - Master → Delegate: Delegate can see master's context via RAG
  - Delegate → Master: Master can collect delegate's response

### 4. Orchestrator Asks Questions
- The master node sends tailored questions to each delegate
- Questions appear as user messages in each delegate's chat

### 5. Delegates Respond
- Each delegate generates an expert response
- Responses are generated sequentially to avoid API rate limits

### 6. Master Synthesizes
- Master collects all delegate responses via edges
- Generates a comprehensive synthesis combining all perspectives
- Final response appears in the master node's chat

## Architecture

### Data Models

#### `OrchestratorSession` (OrchestratorSession.swift)
Tracks the complete orchestration lifecycle:
- `id`, `masterNodeId`, `projectId`
- `originalPrompt` - The user's original question
- `status` - Current phase (proposing, awaitingApproval, spawning, consulting, synthesizing, completed)
- `proposedRoles` - Array of `ProposedRole` objects
- `delegateStatuses` - Tracks each delegate's progress
- `delegateNodeIds`, `masterToDelegateEdgeIds`, `delegateToMasterEdgeIds`
- Timestamps for each phase

#### `ProposedRole`
- `roleId` - References Role.id from roles.json
- `roleName` - Display name
- `justification` - Why this specialist is needed
- `tailoredQuestion` - Specific question for this specialist
- `isApproved` - User can toggle (for future approval UI)

#### `DelegateStatus`
- `id` - Same as delegate node ID
- `roleId`, `roleName`
- `status` - waiting, thinking, responded, failed
- `responsePreview` - First ~100 chars for UI

### Node Model Extensions

Added to `Node.swift`:
- `orchestratorSessionId: UUID?` - Links node to orchestration session
- `orchestratorRoleRaw: String?` - "master" or "delegate"
- `orchestratorRole: OrchestratorRole?` - Computed property
- `isInOrchestration`, `isOrchestrator`, `isDelegate` - Helper properties

### Database Migration

Added columns to `nodes` table:
- `orchestrator_session_id TEXT`
- `orchestrator_role TEXT`

### Services

#### `OrchestratorService` (OrchestratorService.swift)
Singleton service managing orchestration:

```swift
// Step 1: Analyze and propose
func analyzeAndPropose(nodeId:, prompt:, viewModel:) async throws -> OrchestratorSession

// Step 2: Spawn delegate nodes (after user approval)
func executeApprovedPlan(session:, viewModel:) async throws

// Step 3: Send questions to delegates
func consultDelegates(session:, viewModel:) async throws

// Step 4: Synthesize responses in master
func synthesizeResponses(session:, viewModel:) async throws

// Full flow (steps 2-4)
func runOrchestration(session:, viewModel:) async throws
```

### UI Components

#### `ExpertPanelProposalView` (Views/Orchestrator/)
- Shows proposed roles with checkboxes
- Role icon, name, justification
- Expandable to show tailored question
- Credit estimate
- Approve/Cancel buttons

#### `OrchestratorStatusView` (Views/Orchestrator/)
- Shows orchestration progress in master node
- Status icon and description
- Progress bar during consultation
- Delegate status list (waiting/thinking/responded)

#### `OrchestratorBadge`
- Small badge for node headers showing "Orchestrator" or "Specialist"

### Integration Points

#### NodeView
- Added `onJamSquad` callback
- Added "Squad" button in input area (left side)
- Button shows `person.3.fill` icon with "Squad" label

#### NodeItemWrapper
- Passes `onJamSquad` callback to NodeView

#### CanvasView
- `handleJamSquad()` function triggers orchestration
- Currently auto-approves all proposed roles (future: show approval UI)

#### CanvasViewModel
- Added `addEdge()` helper method for cleaner edge creation

## Node Layout

Delegates are positioned in an org-chart style below the master:

```
                    ┌─────────────────┐
                    │   Master Node   │
                    │  (Orchestrator) │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
              ▼              ▼              ▼
        ┌──────────┐  ┌──────────┐  ┌──────────┐
        │ Backend  │  │ Frontend │  │   AI/ML  │
        │ Engineer │  │ Engineer │  │ Engineer │
        └──────────┘  └──────────┘  └──────────┘
```

Positioning algorithm:
- Vertical offset: 500px below master
- Horizontal spacing: 520px between delegates
- Delegates centered horizontally under master

## Edge Connections

Bidirectional edges ensure RAG context flows both ways:

1. **Master → Delegate**: Delegate nodes can access master's conversation history and context through the existing `buildAIContext()` RAG system

2. **Delegate → Master**: Master can collect delegate responses for synthesis

## AI Prompts

### Analysis Prompt
Instructs AI to analyze the question and propose 2-4 specialists from the available roles library. Response must be valid JSON with:
- `needsPanel: boolean`
- `reason: string`
- `roles: [{roleId, justification, question}]`

### Synthesis Prompt
Instructs AI to:
1. Integrate all expert perspectives
2. Highlight consensus points
3. Address conflicts and recommend resolution
4. Provide actionable next steps

## Files Created

| File | Purpose |
|------|---------|
| `JamAI/Models/OrchestratorSession.swift` | Data models for orchestration |
| `JamAI/Services/OrchestratorService.swift` | Core orchestration logic |
| `JamAI/Views/Orchestrator/ExpertPanelProposalView.swift` | Role approval UI |
| `JamAI/Views/Orchestrator/OrchestratorStatusView.swift` | Progress display |

## Files Modified

| File | Changes |
|------|---------|
| `Node.swift` | Added orchestrator fields |
| `Database.swift` | Migration for new columns |
| `CanvasViewModel.swift` | Added `addEdge()` method |
| `NodeView.swift` | Added Squad button, state, callback |
| `NodeItemWrapper.swift` | Pass-through for callback |
| `CanvasView.swift` | `handleJamSquad()` function |

## Future Enhancements

### Phase 2: Approval UI
- Show `ExpertPanelProposalView` before spawning
- User can toggle roles on/off
- User can edit tailored questions

### Phase 3: Status Display
- Show `OrchestratorStatusView` in master node during orchestration
- Real-time progress updates
- Cancel button

### Phase 4: Advanced Features
- Saved panel templates
- Iterative refinement (delegates ask follow-ups)
- Cross-panel discussion
- Custom role creation

## Testing Checklist

- [ ] Squad button appears in standard node input area
- [ ] Button is disabled when prompt is empty
- [ ] Clicking Squad triggers orchestration
- [ ] AI proposes relevant roles
- [ ] Delegate nodes spawn below master
- [ ] Edges connect master ↔ delegates
- [ ] Each delegate has correct Team Member assigned
- [ ] Tailored questions appear in delegate chats
- [ ] Delegates generate responses
- [ ] Master synthesizes all responses
- [ ] Session completes successfully
- [ ] Nodes persist after app restart
- [ ] Edges persist after app restart

## Credit Usage

Estimated credits per orchestration:
- Analysis: ~1-2 credits
- Per delegate (question + response): ~4 credits each
- Synthesis: ~2-3 credits

**Total for 3 delegates: ~15-17 credits**

Consider adding credit warning before orchestration.
