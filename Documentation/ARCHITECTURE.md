# Architecture

Cursor Studio uses a small MVVM-style structure:

- `Models` contains stable Codable library types and normalized hotspots.
- `ThemeStore` owns JSON persistence and Application Support asset lifecycle.
- `ImageImportService` validates and re-encodes imports without retaining the
  source file.
- `CapeImportService` independently decodes Mousecape property lists inside an
  Application Support staging directory. It validates image dimensions before
  decoding, maps known roles through `CapeCursorRoleMapper`, and returns a
  review draft without mutating the library.
- `WindowsCursorImportService` discovers `.cur` and `.ani` recursively, reads
  optional `.inf` role hints, safely extracts ZIP archives, and converts
  Windows images into the same internal cursor representation.
- `ThemeImportDraft` is the shared staging boundary for Mousecape, Windows,
  Marketplace, and future importers. `ThemeStore.commitImportedTheme` performs
  the transactional library commit.
- `ThemePreviewGenerator` writes a bounded 96-pixel cached preview from Arrow,
  another available image, or a generated transparent placeholder.
- `AppViewModel` coordinates editing, applying, restoring, errors, and status.
- `SystemCursorApplying` is the sole system-cursor dependency boundary.
- `CoreGraphicsCursorApplier` is the only production private-API client.
- `CursorReapplicationMonitor` translates lifecycle/display notifications into
  debounced reapplication.
- `Views` contains native SwiftUI library, role-grid, inspector, hotspot, and
  privacy/diagnostic presentation.

`ThemeLibraryDocument.schemaVersion` provides a migration seam. Version 1
entries decode with defaults for point size, representations, animation, and
import metadata. Before migration, `library.json` is copied to a timestamped
`library.backup-v<version>-*.json`. A corrupt JSON library is moved aside with a
timestamp and replaced with the locally generated demo library. Assets remain
in per-theme directories using UUID-derived filenames.

## Transactional theme import

`.cape` data is accepted as an XML or binary property list. Keyed archives and
unknown root structures are rejected. The importer limits file size, cursor
count, representation count, encoded bytes, decoded pixel area, point size,
and frame count.

CUR parsing reads the ICO-compatible directory, extracts hotspots, and wraps
PNG/DIB payloads in a minimal ICO container for ImageIO. ANI parsing walks
bounded RIFF `ACON` chunks, respects `seq`/`rate`, and creates the same vertical
frame strips used by Mousecape.

All normalized PNG strips, first-frame previews, and the theme preview are
written to `ImportStaging/<UUID>`. Cancel or any parse failure removes that
directory. `ThemeStore.commitImportedTheme` moves the complete theme directory
into `Themes/<theme UUID>` and only then persists the library; a persistence
failure moves it back and removes the in-memory entry.

The imported theme no longer depends on its source `.cape`. Unknown cursor
identifiers retain their images, scale, hotspot, and animation metadata as
unassigned entries for future mapping support.

## Resource lifetime

- The UI image cache is capped at 64 objects and approximately 24 MB.
- Import-time `CGImage` objects are local to one actor operation.
- Security-scoped file access is paired with `stopAccessingSecurityScopedResource`.
- Reapplication observers are registered once, debounced, and removed on stop
  or view-model destruction.
- There is no timer or cursor-position polling loop.
- Abandoned staging directories older than 24 hours are removed before import.

## Cursor restoration state

The active theme ID is UI state, not a restoration dependency. The applier
stores WindowServer identifiers, image fingerprints, and opaque system-backup
alias names in `cursor-overrides.json`; it stores no theme ID or asset path.
Before Apply replaces a named CoreGraphics cursor, a pristine copy is
registered under its backup alias. Restore reinstates those named cursors,
rebuilds the `com.apple.cursor.*` table with `CoreCursorUnregisterAll`, selects
the built-in Arrow, verifies the actual registration payloads, and deletes the
ledger and backup aliases.

By default, startup and application termination both run this reset. A user
Restore always clears the active ID first and cancels pending
notification-driven reapplication. Older ledgers without backup aliases are
migrated from the vector cursor resources supplied by macOS itself.

When **Keep cursor active after quitting Cursor Studio** is enabled, a clean
termination leaves WindowServer's registration and the active-theme ID intact.
The next launch first resets registrations through the normal Apply path, then
reapplies that active theme from current library data. A missing or deleted
theme is removed by store validation and falls back to the real system cursor.

## Helper assessment

No privileged helper or daemon is used. WindowServer already owns a global
cursor registration after the client process exits, so keeping a background
process alive would add complexity without changing quit persistence. The main
app can register itself with `SMAppService` as an ordinary login item; this
reapplies the active theme after reboot when persistent mode is enabled.
