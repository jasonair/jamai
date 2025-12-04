# Manual Wiring & Per-Node RAG Implementation

## Overview

This implementation adds Figma/Miro-style manual node wiring and per-node RAG (Retrieval Augmented Generation) to JamAI. Users can now:

1. **Manually connect any two nodes** by dragging from connection points
2. **Build knowledge chains** where connected nodes provide context to each other
3. **Leverage semantic embeddings** for intelligent context retrieval

## Features

### 1. Visual Connection Points

When hovering near a node's edge, connection points appear at the midpoint of each side (top, right, bottom, left).

**UX Behavior:**
- Connection points are 12px circles that appear on hover
- Points scale up and change color when hovered
- Cursor changes to crosshair when hovering a connection point
- Points also appear on all nodes when actively wiring

### 2. Drag-to-Connect Wiring

Click and drag from any connection point to create a wire to another node.

**UX Flow:**
1. Hover near node edge → connection point appears
2. Click and drag from connection point → preview wire follows mouse
3. Drag over target node → node highlights as valid target
4. Release on target → edge created
5. Release on empty canvas → wiring cancelled

**Constraints:**
- Cannot wire a node to itself
- Cannot create duplicate edges (same source → target)
- Edges inherit color from source node

### 3. Per-Node Embeddings

Each node automatically generates a semantic embedding after AI responses.

**How it works:**
- Embeddings are generated using Gemini's `text-embedding-004` model
- Content includes: title, description, and recent conversation
- Embeddings are stored in the database and updated when content changes
- Skipped for local LLM provider (no embedding API)

### 4. Edge-Based RAG Context

When chatting in a node, connected source nodes provide context.

**Context Flow:**
```
[Node A] ──wire──► [Node B]

When chatting in Node B:
- Node A's content is included as context
- Format: "Context from connected knowledge sources: [Node A Title]: <snippet>"
```

**Context Building:**
1. Parent node summary (existing behavior)
2. Connected nodes via incoming edges (NEW)
3. Node's own conversation history

### 5. Multi-Hop Support

The system supports traversing multiple hops for deeper context chains.

```
[Node A] ──► [Node B] ──► [Node C]

When chatting in Node C:
- Direct context: Node B (1 hop)
- Indirect context: Node A (2 hops, available via API)
```

## Files Created

| File | Purpose |
|------|---------|
| `Models/ConnectionSide.swift` | Enum for top/right/bottom/left sides |
| `Views/ConnectionPointView.swift` | Hoverable connection point UI |
| `Views/WirePreviewLayer.swift` | Preview wire during drag |
| `Services/NodeEmbeddingService.swift` | Embedding generation & similarity search |

## Files Modified

| File | Changes |
|------|---------|
| `Models/Node.swift` | Added `embeddingJSON`, `embeddingUpdatedAt`, computed properties |
| `Storage/Database.swift` | Added embedding columns, migration |
| `Views/NodeItemWrapper.swift` | Added connection points overlay, wiring callbacks |
| `Views/CanvasView.swift` | Added WirePreviewLayer, wiring integration |
| `Services/CanvasViewModel.swift` | Added wiring state, methods, edge-based context |

## Database Schema Changes

```sql
-- New columns in nodes table
ALTER TABLE nodes ADD COLUMN embedding_json TEXT;
ALTER TABLE nodes ADD COLUMN embedding_updated_at DATETIME;
```

Migration is automatic - existing databases will be updated on first load.

## API Usage

### Manual Wiring

```swift
// Start wiring from a node
viewModel.startWiring(from: nodeId, side: .right)

// Update wire endpoint during drag
viewModel.updateWireEndpoint(canvasPoint)

// Complete wiring to target
viewModel.completeWiring(to: targetNodeId)

// Cancel wiring
viewModel.cancelWiring()
```

### Embedding Service

```swift
// Generate embedding for a node
let embedding = try await embeddingService.generateEmbedding(for: node)

// Update embedding if needed
let updated = try await embeddingService.updateEmbeddingIfNeeded(for: &node)

// Find relevant connected nodes
let results = try await embeddingService.findRelevantNodes(
    query: userPrompt,
    connectedNodes: connectedNodes,
    topK: 3,
    minSimilarity: 0.3
)

// Build context snippet
let snippet = embeddingService.buildContextSnippet(from: sourceNode)

// Multi-hop context collection
let multiHop = embeddingService.collectMultiHopContext(
    for: node,
    edges: edges,
    nodes: nodes,
    maxHops: 2
)
```

## Testing Checklist

### Manual Wiring
- [ ] Connection points appear on hover near node edges
- [ ] Points appear on all sides (top, right, bottom, left)
- [ ] Clicking and dragging creates preview wire
- [ ] Preview wire follows mouse position
- [ ] Releasing on target node creates edge
- [ ] Releasing on empty canvas cancels wiring
- [ ] Cannot wire node to itself
- [ ] Cannot create duplicate edges
- [ ] Edge inherits source node color
- [ ] Undo/redo works for created edges

### RAG Context
- [ ] Embedding generated after AI response
- [ ] Connected node context appears in AI responses
- [ ] Multiple connected nodes provide combined context
- [ ] Context format is clear and readable
- [ ] Embedding skipped for local LLM provider

### Edge Cases
- [ ] Wiring works during zoom/pan
- [ ] Connection points visible at all zoom levels
- [ ] Large projects with many edges perform well
- [ ] Embedding generation doesn't block UI

## Performance Considerations

1. **Embedding Generation**: Async, non-blocking, happens after AI response
2. **Context Building**: Synchronous but fast (no API calls)
3. **Connection Points**: Only rendered when node is hovered or wiring active
4. **Wire Preview**: Lightweight bezier curve rendering

## Future Enhancements

1. **Semantic Ranking**: Use embeddings to rank connected nodes by relevance
2. **Edge Labels**: Add labels to edges for relationship types
3. **Bidirectional Edges**: Support two-way connections
4. **Edge Deletion UI**: Right-click on wire to delete
5. **Connection Limits**: Optional limit on incoming/outgoing connections
6. **Visual Indicators**: Show connection count badge on nodes

## Cost Considerations

- Embedding generation: ~$0.0001 per node (Gemini text-embedding-004)
- 1000 nodes ≈ $0.10 for initial embedding
- Updates only when content changes
- No cost for local LLM provider (embeddings skipped)
