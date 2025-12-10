# PDF Knowledge Base Implementation

Implemented PDF document nodes that use Gemini File Search API for intelligent RAG-based context retrieval.

## Overview

PDF nodes are compact knowledge containers that can be connected to regular chat nodes. When a chat node is connected to a PDF node, all AI responses will automatically search the PDF content for relevant information using Gemini's File Search tool.

## Cost Comparison

| Approach | Initial Indexing | Query-Time | Storage |
|----------|-----------------|------------|---------|
| **Gemini File Search** | $0.15/1M tokens (one-time) | **FREE** | **FREE** |
| **Traditional RAG** | $0.01/1M tokens | $0.01/1M tokens per query | Self-managed |

**Winner: Gemini File Search** - Pay once on upload, unlimited free queries thereafter.

## Features

### PDF Node Display
- **Compact size**: 200×80px (roughly 50% smaller than standard nodes)
- **Visual elements**: PDF icon, filename, status indicator
- **Status states**: Ready, Uploading, Indexed, Re-indexing needed, Error
- **Hover actions**: Delete button appears on hover

### Automatic PDF Indexing
- PDF files are automatically uploaded to Gemini File API on node creation
- Files are indexed for semantic search
- Status indicator shows indexing progress
- Indexed files expire after 48 hours and are automatically re-uploaded when needed

### Smart Context Retrieval
When a chat node is connected to one or more PDF nodes via wires:
1. User's query is sent to Gemini File Search
2. Relevant passages are extracted from the PDF(s)
3. Context is injected into the AI prompt
4. AI responds with information grounded in the PDF content

## How to Use

### Adding PDFs to Canvas
1. **Drag and Drop**: Drag a PDF file from Finder onto the canvas
2. PDF node appears at drop location
3. File automatically uploads and indexes in background

### Connecting PDFs to Nodes
1. Hover over a PDF node to see connection points
2. Click and drag from a connection point to a chat node
3. Wire connects PDF → Chat node
4. All subsequent AI responses in that chat node will search the PDF

### Multi-PDF Support
- Connect multiple PDF nodes to a single chat node
- File Search queries across all connected PDFs simultaneously
- Sources are cited in the response

## Files Created

### Services
- `JamAI/Services/PDFFileService.swift` - Upload PDFs to Gemini File API, manage file lifecycle
- `JamAI/Services/PDFSearchService.swift` - Query PDFs using File Search, build context

### Views
- `JamAI/Views/PDFNodeView.swift` - Compact PDF node display

## Files Modified

### Models
- `JamAI/Models/Node.swift` - Added `pdf` NodeType and fields: `pdfFileUri`, `pdfFileName`, `pdfFileId`, `pdfData`

### Storage
- `JamAI/Storage/Database.swift` - Migration for PDF columns

### Services
- `JamAI/Services/CanvasViewModel.swift`:
  - Added `pdfSearchService` property
  - Added `createPDFNode()`, `uploadPDFToGemini()`, `ensurePDFFileActive()` methods
  - Modified `buildAIContext()` to be async and include PDF search for connected PDF nodes

### Views
- `JamAI/Views/NodeItemWrapper.swift` - Added PDF node rendering case
- `JamAI/Views/CanvasView.swift` - Added PDF drag-and-drop support

## Technical Details

### File Expiration
Gemini File API files expire after 48 hours. The implementation handles this by:
1. Storing raw PDF data in the database (`pdfData` column)
2. Checking file status before queries
3. Automatically re-uploading expired files

### Database Schema
```sql
-- New columns in nodes table
pdf_file_uri TEXT,    -- Gemini File API URI (files/xxx)
pdf_file_name TEXT,   -- Original filename
pdf_file_id TEXT,     -- Gemini file ID for status checks
pdf_data BLOB         -- Raw PDF bytes for re-upload
```

### API Endpoints Used
- `POST https://generativelanguage.googleapis.com/upload/v1beta/files` - Resumable upload
- `GET https://generativelanguage.googleapis.com/v1beta/files/{fileId}` - Check status
- `DELETE https://generativelanguage.googleapis.com/v1beta/files/{fileId}` - Delete file
- `POST https://generativelanguage.googleapis.com/v1beta/{model}:generateContent` - Query with file_data

## Future Enhancements

1. **Toolbar PDF button** - Add explicit upload button in addition to drag-drop
2. **PDF preview** - Show thumbnail or first page preview
3. **Multiple file types** - Support DOCX, TXT, JSON (already supported by File Search)
4. **Citation highlighting** - Show which parts of the PDF were used
5. **Page number references** - Include page numbers in citations
