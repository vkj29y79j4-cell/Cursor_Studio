# Private cursor API technical note

## Status

Cursor Studio replaces the real global macOS cursor by registering images with
the user's WindowServer connection. This is an unsupported implementation
detail of macOS, not a public SDK contract. The code must be retested after
major operating-system releases.

The standalone proof was built and run on:

- macOS 26.5.2 (25F84)
- Apple Silicon
- Xcode 26.6 (17F113), Swift 6.3.3
- System Integrity Protection enabled

The proof registered an original magenta Arrow image, copied the registration
back from WindowServer, verified its 64×64 representation and `(4, 4)` hotspot,
kept it active for 12 seconds, and restored the default cursor. This confirmed
that the visible system registration changed; no overlay or simulated pointer
was involved.

## Isolation boundary

All production private-API use lives in
`Cursor Studio/Services/CoreGraphicsCursorApplier.swift` behind:

```swift
@MainActor
protocol SystemCursorApplying {
    func apply(theme: CursorTheme) async throws
    func restoreSystemDefault() async throws
}
```

View models, persistence, import, hotspot editing, and SwiftUI views depend only
on that protocol. Tests substitute a mock implementation.

## Runtime symbols

Symbols are resolved dynamically with `dlopen`/`dlsym` rather than declared in
a bridging header. Cursor Studio tries the CoreGraphics `CGS` entry points and
their SkyLight `SLS` equivalents where applicable:

- `CGSMainConnectionID`
- `CGSRegisterCursorWithImages` / `SLSRegisterCursorWithImages`
- `CGSRemoveRegisteredCursor` / `SLSRemoveRegisteredCursor`
- `CoreCursorUnregisterAll`
- `CoreCursorSet`
- `CGSCursorNameForSystemCursor` / `SLSCursorNameForSystemCursor`
- `CGSSetDockCursorOverride` / `SLSSetDockCursorOverride`
- `CGSCreateRegisteredCursorImage` / `SLSCreateRegisteredCursorImage`
- `CGSCopyRegisteredCursorImages` / `SLSCopyRegisteredCursorImages`
- `CoreCursorCopyImages`

On the validated macOS build, runtime name discovery reported Arrow aliases
including `com.apple.coregraphics.Arrow`, `ArrowCtx`, and `ArrowS`. The
production applier discovers Arrow and I-Beam aliases at runtime and combines
them with stable role-specific identifier candidates.

If any required symbol is unavailable, Apply fails with a user-readable private
API error. Cursor Studio does not fall back to a fake cursor.

## Apply and rollback

An Apply operation:

1. Resolves the private API and validates the WindowServer connection.
2. Restores system registrations so missing theme roles use macOS defaults.
3. Copies pristine named system registrations to opaque backup aliases and
   persists that map before replacing the first cursor.
4. Loads each configured role's copied Application Support asset.
5. Uses validated Mousecape representation strips and point dimensions when
   present, or re-renders a standalone PNG to premultiplied sRGB with a maximum
   dimension of 64 pixels.
6. Converts the normalized hotspot into the registered bitmap's coordinate
   space and clamps it to the current private API's practical range.
7. Registers all known aliases for that role.

If any configured role cannot be registered, the operation logs the failure,
unregisters custom cursors, asks CoreCursor to restore its built-ins, and marks
the theme inactive.

Each successful custom registration writes its identifier and rendered
fingerprint to `cursor-overrides.json`. The ledger also contains only the
opaque names of WindowServer backup registrations—never a theme ID or asset
path—so restoration still works after deleting a theme, removing Marketplace
content, relaunching the app, or rebooting.

Restore first reinstates named aliases such as Arrow, I-Beam, Copy, Alias, and
Wait from their pristine backups. It then calls `CoreCursorUnregisterAll`,
recreates all 45 built-in `com.apple.cursor.*` registrations, disables the Dock
override, and selects Arrow. Registrations are verified with
`CGSCopyRegisteredCursorImages`, avoiding the stale cache returned by
`CGSCreateRegisteredCursorImage` after a reset. Older ledgers without backups
are migrated from the vector cursor PDFs and metadata shipped in HIServices.
Only after verification does Cursor Studio delete the ledger and backup
aliases.

## Reapplication

While Cursor Studio is running and a theme is active, reapplication is
scheduled from system notifications for wake, accessibility display-option
changes, screen-parameter changes, and application activation. Events are
debounced by 750 ms. There is no continuous pointer or timer polling.

By default, application termination performs the same verified restore.
Persistent mode instead leaves WindowServer's registration in place and keeps
the active-theme ID. A later launch still enters through Apply, which restores
the current registration table before creating fresh backups and applying the
theme. Manual Restore is unconditional in either mode.

## Security and operational properties

- No Accessibility permission is requested.
- No cursor-following window is created.
- No root daemon or privileged helper is installed.
- SIP remains enabled.
- No protected system file is read or modified.
- App Sandbox and hardened runtime are disabled because unsupported dynamic
  WindowServer calls are incompatible with the intended GitHub-source build.
- The application is local-only and performs no networking.

## Maintenance checklist

For each major macOS release:

1. Build and run `ProofOfConcept/SystemCursorProof.swift`.
2. Confirm the proof reports `APPLIED`, `VERIFIED`, and `RESTORED`.
3. Visually confirm there is one responsive pointer with no lag.
4. Test Arrow, Pointing Hand, I-Beam, resize, and Restore in several apps.
5. Confirm wake and display-change reapplication.
6. Review diagnostics for new `CGError` values or changed names.
7. Repeat Apply → Restore at least five times and repeat Restore alone at least
   three times to verify idempotence.
