# Jam AI — Product Description

## One-Line Summary

**Jam AI is a visual AI thinking canvas that lets you map ideas as interconnected nodes, chat with AI specialists, and orchestrate multi-agent teams to solve complex problems.**

---

## What is Jam AI?

Jam AI is a native macOS application that reimagines how you interact with AI. Instead of linear chat threads, Jam AI provides an **infinite canvas** where your thoughts, conversations, and AI responses become visual nodes that you can connect, branch, and organize spatially.

Think of it as **FigJam meets ChatGPT** — a whiteboard for your ideas where every sticky note can have its own AI conversation, and those conversations can be linked together to build knowledge chains.

---

## Core Concept

### Visual Thinking with AI

Traditional AI chat is linear and limiting. You ask a question, get an answer, and the context is lost as you scroll up. Jam AI breaks this pattern by letting you:

- **Create nodes** for different topics, ideas, or questions
- **Connect nodes** with wires to show relationships and flow context between them
- **Branch conversations** to explore multiple directions from a single idea
- **Assign AI specialists** to nodes for domain-specific expertise
- **Orchestrate teams** of AI agents to tackle complex, multi-faceted problems

---

## Key Features

### 1. Infinite Canvas
- **Pan and zoom** with Metal-accelerated 60fps rendering
- **Drag nodes** anywhere to organize your thinking spatially
- **Resize nodes** to fit your content
- **Color-code nodes** for visual organization
- Scales to **thousands of nodes** without performance degradation

### 2. AI-Powered Conversations
- **Streaming responses** from Gemini 2.0 Flash (or local LLMs via Ollama)
- **Context inheritance** — child nodes automatically receive parent context
- **Multi-turn conversations** within each node
- **Auto-generated titles** — AI summarizes your conversation into a title
- **Rich markdown rendering** — tables, code blocks, headers, lists

### 3. Manual Wiring & Knowledge Chains
- **Connect any two nodes** by dragging from connection points
- **Context flows through wires** — connected nodes share knowledge via RAG
- **Multi-hop context** — traverse up to 2 hops for deeper knowledge chains
- **Bidirectional edges** — information flows both ways
- **Visual wire colors** inherit from source node for easy tracking

### 4. AI Team Members (30+ Specialists)
Attach expert AI personas to any node. Each specialist has role-specific prompts and expertise:

**Business & Leadership:**
- CEO, CTO, CPO, Co-Founder
- Project Manager, Sales Representative

**Technical:**
- Full-Stack Engineer, Python Developer, Swift/SwiftUI Developer
- AI/ML Engineer, Blockchain Developer, C++ Developer, PHP Developer
- Data Scientist

**Research:**
- Research Analyst, Academic Researcher, Market Researcher
- UX Researcher, Competitive Intelligence Analyst
- Scientific Researcher, Policy Researcher

**Creative & Design:**
- UX Designer, Content Writer, Digital Marketer

**Finance:**
- UK Accountant, US Accountant

Each role has **4 experience levels** (Junior → Expert) with progressively sophisticated prompts.

### 5. Jam Squad — Multi-Agent Orchestration
For complex problems that need multiple perspectives:

1. **Trigger Jam Squad** on any node with a complex question
2. **AI analyzes** your question and proposes 2-4 relevant specialists
3. **Delegate nodes spawn** below your master node in an org-chart layout
4. **Each specialist** receives a tailored question based on their expertise
5. **Specialists respond** with domain-specific insights
6. **Master synthesizes** all perspectives into a unified answer

**Expert Routing:** After orchestration, follow-up questions are automatically routed to the most relevant specialist.

### 6. Notes & Annotations
- **Note nodes** — FigJam-style sticky notes with always-editable text
- **Text nodes** — Simple text labels for canvas organization
- **Image nodes** — Paste or upload images directly to canvas
- **Shape nodes** — Rectangles and ellipses for visual grouping

### 7. Voice Input
- **Voice-to-text transcription** using Gemini 2.0 Flash
- **Real-time waveform visualization** during recording
- **60-second max recording** with auto-stop
- **Append to existing text** — record multiple times to build prompts

### 8. Image Understanding
- **Upload images** to include in your prompts
- **AI analyzes images** and responds with visual context
- **Paste from clipboard** — Cmd+V to add screenshots
- **Automatic compression** for optimal API usage

### 9. Web Search Integration
- **Toggle web search** per message
- **AI searches the web** for current information
- **Cites sources** in responses
- Powered by Perplexity API

### 10. Project Management
- **Native .jam files** — double-click to open
- **Auto-save** every 30 seconds with rolling backups
- **Undo/Redo** — 200 steps of history (Cmd+Z / Cmd+Shift+Z)
- **Copy/Paste nodes** — duplicate entire branches
- **Export** to JSON or Markdown
- **Multi-project tabs** — work on multiple canvases simultaneously

### 11. Outline View
- **Hierarchical view** of all nodes
- **Quick navigation** — click to jump to any node
- **Search across all nodes** and conversations
- **Bookmarks** — save important passages for quick reference

### 12. Local LLM Support
- **Ollama integration** for privacy-first local AI
- **No internet required** for local models
- **No credit usage** when using local LLMs
- **Provider switching** — seamlessly switch between local and cloud AI

---

## Pricing

| Plan | Price | Credits/Month | Key Features |
|------|-------|---------------|--------------|
| **Free** | $0 | 100 | 2-week Pro trial, Local + Gemini 2.0, All team members |
| **Pro** | $15 | 1,000 | Everything in Free + more credits |
| **Teams** | $30 | 1,500/user | Everything in Pro + team features |
| **Enterprise** | Custom | 5,000/user | Dedicated account manager |

**All plans include:** Unlimited team members, all experience levels, unlimited saved Jams.

---

## Who is Jam AI For?

### Researchers & Analysts
- Map out research topics as connected nodes
- Attach Research Analyst or Academic Researcher specialists
- Build knowledge chains that preserve context across topics
- Use Jam Squad to get multi-perspective analysis

### Product Managers & Strategists
- Brainstorm features with AI assistance
- Connect user stories to technical requirements
- Orchestrate teams of specialists (UX, Engineering, Marketing)
- Visualize product roadmaps and dependencies

### Developers & Technical Writers
- Document architecture with connected nodes
- Get code help from specialized AI engineers
- Branch conversations to explore different solutions
- Export documentation to Markdown

### Founders & Business Leaders
- Strategic planning with AI advisors
- Explore business models from multiple angles
- Get perspectives from CEO, CTO, CPO specialists
- Synthesize complex decisions with Jam Squad

### Writers & Content Creators
- Outline articles and books visually
- Get feedback from Content Writer specialists
- Branch storylines and explore alternatives
- Organize research and sources spatially

### Students & Learners
- Map out study topics and connections
- Get explanations from subject-matter experts
- Build visual knowledge maps
- Review and revise with AI assistance

---

## Technical Highlights

- **Native macOS app** — SwiftUI with Metal acceleration
- **SQLite storage** — Fast, reliable local database
- **60fps performance** — Smooth pan, zoom, and drag
- **GPU rasterization** — Cached rendering for complex content
- **Offline capable** — Works with local LLMs without internet
- **Privacy-first** — Your data stays on your device

---

## Key Differentiators

| Feature | Jam AI | Traditional Chat AI |
|---------|--------|---------------------|
| **Interface** | Infinite visual canvas | Linear chat thread |
| **Context** | Flows through connected nodes | Lost as you scroll |
| **Branching** | Unlimited parallel explorations | Single conversation |
| **Specialists** | 30+ AI personas with expertise | Generic assistant |
| **Multi-agent** | Jam Squad orchestration | Single AI response |
| **Organization** | Spatial, visual, connected | Chronological only |
| **Persistence** | Native files, auto-save, backups | Session-based |

---

## Sample Use Cases

### 1. Product Strategy Session
Create a master node with your product question → Trigger Jam Squad → Get insights from Product Manager, UX Designer, and Full-Stack Engineer → Synthesize into actionable strategy.

### 2. Research Deep Dive
Create nodes for each research topic → Connect related topics with wires → Attach Research Analyst to each → Context flows between nodes as you explore.

### 3. Technical Architecture
Map out system components as nodes → Connect with data flow wires → Attach CTO to architecture node, Engineers to implementation nodes → Document decisions visually.

### 4. Content Planning
Create nodes for article sections → Branch to explore different angles → Attach Content Writer for drafting → Export final structure to Markdown.

### 5. Learning & Study
Create nodes for each concept → Connect prerequisites → Ask questions in each node → Build a visual knowledge map over time.

---

## Summary

**Jam AI transforms AI interaction from linear chat into visual thinking.** 

Map your ideas spatially. Connect them with wires. Attach AI specialists. Orchestrate teams. Build knowledge that compounds.

It's not just a better way to chat with AI — it's a new way to think with AI.
