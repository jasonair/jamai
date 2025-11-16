# Personalities Feature - Design & Implementation Plan

## Overview

The **Personalities** feature adds a per-node "Personality" selector that controls *how* an attached expert (team member role) thinks and responds, without requiring the user to name that expert.

- **Role** (already exists): what the AI is an expert in, e.g. `Expert UK Accountant`, `Staff iOS Engineer`, `Growth PM`.
- **Personality** (new): how that expert approaches problems, e.g. `Generalist`, `Analyst`, `Strategist`, `Creative`, `Skeptic`, `Clarifier`.

This replaces the need for users to invent custom names for team members. Nodes will show the **role** as the main identity, with a **Personality** control underneath to switch thinking style per node.

---

## Goals

- Remove friction of naming team members manually.
- Make the node header read like a real collaborator: "Expert UK Accountant" instead of an arbitrary name.
- Give users a small set of **universal, role-agnostic personalities** they can switch between on the fly.
- Store personality **per node**, so the same role can behave differently in different contexts.
- Wire personalities into prompt construction so they meaningfully change AI behavior.

---

## v1 Personality Set

Label in UI: **Personality**

Each personality has:
- A **label** shown in the UI.
- A **short description** for tooltips / help.
- A **prompt snippet** appended to the system prompt.

### 1. Generalist (default)
- **Label**: `Generalist`
- **Description**: Balanced, pragmatic, mixes explanation and recommendations.
- **Prompt snippet**:
  > Act as a balanced generalist. Combine clear explanation, sensible structure and practical recommendations. Use evidence and numbers when helpful, but don’t overcomplicate. When there are multiple reasonable options, briefly compare them and suggest a pragmatic next step.

### 2. Analyst
- **Label**: `Analyst`
- **Description**: Evidence-based, explicit assumptions, structured comparisons.
- **Prompt snippet**:
  > Be careful, evidence-based and explicit about assumptions and numbers. Compare options using concrete criteria, show calculations where relevant, and highlight uncertainties or missing data. Prefer structured reasoning over anecdotes.

### 3. Strategist
- **Label**: `Strategist`
- **Description**: Options, trade-offs, longer-term impact and direction.
- **Prompt snippet**:
  > Think in terms of options, trade-offs and longer-term consequences. Lay out alternative approaches, compare their pros and cons, and explain how they affect risks, effort and outcomes over time. Help the user choose a path, not just make a single local decision.

### 4. Creative
- **Label**: `Creative`
- **Description**: Imaginative, connects ideas and perspectives, explores alternatives.
- **Prompt snippet**:
  > Generate imaginative ideas and unexpected connections between concepts. Bring in analogies from other domains, explore alternative framings, and propose novel combinations or twists. It’s okay to be more playful and speculative, as long as you stay relevant to the user’s goal.

### 5. Skeptic
- **Label**: `Skeptic`
- **Description**: Stress-tests assumptions, looks for risks and failure modes.
- **Prompt snippet**:
  > Stress-test the user’s ideas and your own suggestions. Look for hidden assumptions, edge cases, risks and failure modes. Politely challenge weak reasoning, point out where something could go wrong, and propose mitigations or safer alternatives.

### 6. Clarifier
- **Label**: `Clarifier`
- **Description**: Simplifies, rephrases, structures information clearly.
- **Prompt snippet**:
  > Make things easy to understand. Rephrase complex ideas in plain language, organize information into clear sections or lists, and give small examples when helpful. Surface the key points first, then details. Check for ambiguity and resolve it.

---

## Removing Custom Names

The existing Team Members system allows an optional **custom name** for each team member. With Personalities, we will:

- **Remove the custom name field** from the Team Member configuration UI.
- Stop using the name in prompts and UI.
- Make the **role** the primary identity shown in the node header.

Effectively, users no longer have to name their AI collaborators. Instead, they:
- Choose a **role** (e.g. Expert UK Accountant).
- Choose a **personality** (e.g. Strategist, Creative, etc.) per node.

Existing projects that already have custom names:
- We will ignore the name in the new UI and prompt assembly.
- Names may remain in stored JSON for backward compatibility but are treated as legacy.

---

## Data Model Changes

### Personality Enum

Introduce a `Personality` enum in Swift, with metadata:

- `case generalist`
- `case analyst`
- `case strategist`
- `case creative`
- `case skeptic`
- `case clarifier`

Each case should provide:
- `displayName: String` — label for UI.
- `shortDescription: String` — tooltip / help text.
- `promptSnippet: String` — system prompt addition.

### Per-Node Personality

Personality is stored **per node**, not globally per team member:

- Add an optional `personality` field to `Node` (e.g. `personalityRawValue: String?` persisted, mapped to `Personality`).
- Default behavior:
  - New nodes: `personality = .generalist`.
  - Existing nodes (on load): if no personality stored, default to `.generalist`.

This allows the same role (e.g. Expert UK Accountant) to behave differently in different nodes, depending on the chosen personality.

> Note: We may later allow a default personality on `TeamMember` for newly attached roles, but v1 behavior is purely per-node.

### Persistence & Migration

- Update node serialization / database schema to include the personality field.
- Treat missing personality as `.generalist` at runtime (no user-facing migration dialog).
- Keep existing `team_member_json` structure compatible; personality is additional, not breaking.

---

## UI Changes

### Node Header

Update `NodeView` header to:

- **Replace custom name with role**:
  - Header title shows the role (e.g. `Expert UK Accountant`) instead of a user-defined name.
- **Add Personality control**:
  - Show a small control under the role, e.g.: `Personality: Generalist ▾`.
  - Clicking opens a menu to choose among the six personalities.
  - Changes are applied immediately and persisted per node.

This makes the node read like:

```
Expert UK Accountant
Personality: Strategist ▾
```

### Team Member Modal

- Remove the **custom name input field**.
- Keep role selection, experience level, and any plan-tier gating.
- Optionally show a note that behavior is further shaped by the node’s Personality, which can be switched from the node header.

---

## Prompt Assembly

Prompt assembly already incorporates Team Member role + experience level. With Personalities, we extend this:

1. Determine the node’s attached Team Member (if any) and role.
2. Determine the node’s Personality (default `.generalist` if unset).
3. Build system prompt as:

   ```
   [Base JamAI System Prompt]

   # Team Member Role
   You are an [ExperienceLevel] [RoleName].

   [Role-specific system prompt for the selected experience level]

   # Personality
   [Personality-specific prompt snippet]

   # Additional Instructions
   [Any user-specified addendum, if supported]
   ```

4. Pass this assembled system prompt to the AI provider for all node conversations.

Changing the Personality on a node changes only the `# Personality` section, keeping role and experience level intact.

---

## Configuration Location (In-App vs Cloud)

- **Source of truth**: v1 ships with Personality definitions **in the app** (enum + prompt snippets).
- **Future override** (optional):
  - We may allow a remote configuration to override these snippets.
  - If remote fetch fails, the app falls back to built-in defaults.

This keeps behavior deterministic per app version but allows future tuning without forcing updates.

---

## Analytics (Optional)

To understand how Personalities are used, we can track:

- `personality_selected` — when a user explicitly chooses a Personality on a node.
  - Properties: `personality`, `roleId`, `projectId`, `nodeId`.
- `personality_changed` — when a node switches from one Personality to another.
  - Properties: `oldPersonality`, `newPersonality`, `roleId`, `projectId`, `nodeId`.

This can inform future refinements (e.g. which personalities are most useful, which are rarely used, whether default `Generalist` is sufficient in many cases).

---

## Implementation Order (v1)

1. **Model Layer**
   - Add `Personality` enum + metadata.
   - Add per-node personality field with default `.generalist`.
   - Update persistence and migration behavior.

2. **Node UI**
   - Replace name with role in `NodeView` header.
   - Add Personality selector bound to node’s personality.

3. **Team Member UI**
   - Remove custom name input from `TeamMemberModal`.
   - Ensure tray and modal reflect role-centric design.

4. **Prompt Wiring**
   - Inject Personality prompt snippet into system prompt assembly.
   - Verify different personalities feel meaningfully different for the same role.

5. **Optional Analytics & Cloud Overrides**
   - Add event logging for Personality selection.
   - (Later) add remote configuration to override prompt snippets when needed.
