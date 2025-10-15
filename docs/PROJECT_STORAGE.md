# JamAI Project Storage and Cross‑Platform Adapter Guide

This document describes the on‑disk project format (the ".jam" bundle), the adapter abstraction used by JamAI to support multiple platforms, and concrete guidance for Windows and Web implementations.

## Summary

- **Bundle format**: A project is a directory with extension `.jam` that contains:
  - `metadata.json` — portable JSON metadata with basic project info.
  - `data.db` — a SQLite 3 database with all graph data (projects, nodes, edges, RAG tables).
- **Abstraction**: All file system access goes through a `StorageAdapter` so platform builds can customize security, defaults, and I/O.
- **macOS**: Uses `MacStorageAdapter` with security‑scoped bookmarks. SQLite journaling is configured to avoid provider restrictions.
- **Windows**: Implement `WinStorageAdapter` (no security scopes). SQLite can use WAL by default with fallback to MEMORY if provider denies `-wal` files.
- **Web**: Implement `WebStorageAdapter` targeting OPFS/File System Access API and SQLite WASM. Import/export `.jam` packages (zip) for interop.

---

## Bundle Format (.jam)

A JamAI project is a folder (package) named `<projectName>.jam/` containing:

```
My Project.jam/
  metadata.json
  data.db
```

### `metadata.json` schema

- `version`: string — schema/version of the metadata file, e.g. `"1.0"`.
- `projectId`: string (UUID) — the project identifier.
- `projectName`: string — display name.
- `createdAt`: ISO 8601 string — creation time.
- `updatedAt`: ISO 8601 string — last update time.

Example:

```json
{
  "version": "1.0",
  "projectId": "e2f7f1a2-5a3e-4f8c-bc9a-6e7d8f9a0b1c",
  "projectName": "My Project",
  "createdAt": "2025-10-15T17:41:22Z",
  "updatedAt": "2025-10-15T17:59:01Z"
}
```

### `data.db` schema

- SQLite 3 database managed by GRDB migrations.
- Tables include `projects`, `nodes`, `edges`, `rag_documents`, `rag_chunks`, plus indexes.
- Cross‑platform safe: SQLite pages are platform‑neutral; no endianness issues for normal use.

### Journaling

- Journaling mode is configured by the app during open.
- On macOS we currently set `journal_mode=MEMORY` to avoid restrictions from sync providers (no `-journal` / `-wal` files).
- On Windows, prefer `WAL` for durability; fallback to `MEMORY` if the target location forbids sidecar files.
- On Web, use SQLite WASM with OPFS; `MEMORY` or `TRUNCATE` journaling is recommended depending on the WASM runtime.

---

## StorageAdapter Contract

Defined in `JamAI/Storage/StorageAdapter.swift`:

- `func defaultSaveLocation(for project: Project) throws -> URL`
  - Suggest a default save location (without `.jam`), platform‑appropriate.
- `func ensureProjectBundle(at baseURL: URL) throws -> URL`
  - Ensure `<baseURL>.jam/` exists and return the bundle directory URL.
- `func normalizeProjectURL(_ url: URL) -> URL`
  - Ensure a URL points to the `.jam` directory.
- `@discardableResult func startAccessing(_ bundleURL: URL) -> Bool`
- `func stopAccessing(_ bundleURL: URL)`
  - Platform hooks; no‑ops on non‑macOS.
- `func openWritableDatabase(at bundleURL: URL) throws -> Database`
  - Open a write‑capable SQLite connection at `bundleURL/data.db`.
- `func saveMetadata(_ project: Project, at bundleURL: URL) throws`
  - Atomically write `metadata.json`.

`DocumentManager` uses the adapter exclusively to:

- Create/open bundles.
- Open a writable database connection.
- Save metadata atomically.

`JamAIApp` (`AppState`) manages long‑lived access (security scope, tab lifecycle) and reuses the same `Database` per tab to avoid read‑only handles.

---

## Current Implementations

- `DefaultStorageAdapter` (non‑AppKit platforms default):
  - Creates the `.jam` directory and `data.db` using Foundation APIs.
  - No security scope; `startAccessing`/`stopAccessing` are no‑ops.
- `MacStorageAdapter` (macOS):
  - Wraps security‑scoped resource access with `startAccessingSecurityScopedResource()`.
  - Same bundle layout and file semantics as default.
- `Database.setup(at:)`:
  - Opens a `DatabaseQueue` and sets PRAGMAs outside transactions.
  - macOS build currently favors `PRAGMA journal_mode=MEMORY; PRAGMA temp_store=MEMORY;` and enables foreign keys.
  - Includes logging/diagnostics and safe fallbacks.

---

## Windows Implementation Plan

Create `WinStorageAdapter` conforming to `StorageAdapter`:

- **Security**: No security‑scoped bookmarks. `startAccessing`/`stopAccessing` return `false` / no‑op.
- **Paths**: Use Known Folders (e.g., `Documents\JamAI Projects\<name>`). Ensure directories with intermediate creation.
- **Bundle**: Same `.jam/` directory with `metadata.json` and `data.db`.
- **SQLite**:
  - Try `PRAGMA journal_mode=WAL` and `PRAGMA synchronous=NORMAL` outside transactions.
  - If the DB path is on a provider that disallows `-wal`/`-shm`, fallback to `PRAGMA journal_mode=MEMORY`.
  - Always enable `PRAGMA foreign_keys=ON`.
- **Atomic writes**: Use write‑to‑temp + replace for `metadata.json` (Foundation’s `.atomic` or manual temp file replace).
- **File locking**: Rely on SQLite’s cross‑platform locking. Avoid multiple writers to the same DB from different processes.

Minimal code sketch:

```swift
struct WinStorageAdapter: StorageAdapter {
    func defaultSaveLocation(for project: Project) throws -> URL { /* Documents/JamAI Projects */ }
    func ensureProjectBundle(at baseURL: URL) throws -> URL { /* create <base>.jam/ */ }
    func normalizeProjectURL(_ url: URL) -> URL { /* append .jam if needed */ }
    @discardableResult func startAccessing(_ bundleURL: URL) -> Bool { false }
    func stopAccessing(_ bundleURL: URL) {}
    func openWritableDatabase(at bundleURL: URL) throws -> Database { /* Database().setup(at: bundleURL/appending("data.db")) */ }
    func saveMetadata(_ project: Project, at bundleURL: URL) throws { /* atomic write */ }
}
```

> Note: Windows builds can immediately read existing `.jam` bundles created on macOS. SQLite files and JSON are portable.

---

## Web Implementation Plan

Create `WebStorageAdapter` conforming to `StorageAdapter`:

- **Storage**: Use OPFS (Origin Private File System) via the File System Access API for persistent storage in the browser. Fall back to in‑memory if not available.
- **Packaging**: For import/export, zip/unzip the `.jam` directory so users can load/save projects as a single file:
  - Import flow: User selects a `.jam` (zip) → Unpack to OPFS → Set up `metadata.json` + `data.db` → Open.
  - Export flow: Pack `metadata.json` + `data.db` from OPFS into a zip → Download.
- **SQLite**: Use SQLite WASM:
  - Back the DB with OPFS; configure `PRAGMA journal_mode=MEMORY` or `TRUNCATE` as supported by the WASM runtime.
  - Maintain the same schema and migrations.
- **Security**: `startAccessing`/`stopAccessing` are no‑ops; permissions managed by the browser prompt.

Adapter responsibilities remain the same; only the I/O layer changes to OPFS APIs bridged from Swift (or JS interop if needed).

---

## Compatibility Considerations

- **Portability**: SQLite and JSON are cross‑platform. Paths, separators, and case sensitivity are handled by the adapter.
- **Sync providers**: If a target path is in iCloud/Dropbox/OneDrive, prefer `MEMORY` journaling or ensure provider allows WAL sidecar files.
- **Atomicity**: Use atomic writes for `metadata.json` and keep a single active writer for `data.db` per project instance.
- **Validation**: Validate `metadata.json` on load; gracefully handle missing fields and version upgrades.

---

## Versioning & Migrations

- `metadata.json` includes a `version` field. When adding fields, bump the version and keep loaders backward‑compatible.
- SQLite migrations are handled by GRDB; keep them idempotent with `ifNotExists` patterns.
- When making breaking changes, provide a migration path and a way to export/import as JSON.

---

## Test Matrix

- **macOS**: Create/open/save; autosave; close/reopen; location in Documents and in a synced folder.
- **Windows**: Same as macOS; additionally verify WAL creation vs MEMORY fallback.
- **Web**: Import (zip) → open → edit → save → export (zip); refresh persistence in OPFS.

---

## File Map (for reference)

- `JamAI/Storage/StorageAdapter.swift` — protocol and default adapter
- `JamAI/Storage/MacStorageAdapter.swift` — macOS adapter
- `JamAI/Storage/DocumentManager.swift` — high‑level project I/O
- `JamAI/Storage/Database.swift` — SQLite setup and migrations
- `JamAI/JamAIApp.swift` — app state and security‑scope lifecycle (macOS)

---

## FAQ

- **Can Windows/Web open a project created on macOS?**
  Yes. The `.jam` directory is platform‑neutral; it contains JSON + SQLite.

- **What if a storage location blocks sidecar files?**
  Use `MEMORY` journaling (no `-wal`/`-journal` on disk). The adapters should detect and fall back.

- **Do we need to change the bundle format for Web?**
  No. For Web we import/export the same structure via a zip container and store its contents in OPFS.
