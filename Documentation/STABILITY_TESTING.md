# Stability and manual verification

## Automated coverage

The synthetic fixtures in `Cursor StudioTests/CapeImportTests.swift` contain
only locally generated pixels and metadata. Tests cover:

- case-insensitive `.cape` detection;
- valid binary-plist parsing;
- partial themes and unknown roles;
- point/pixel and Retina scale conversion;
- hotspot conversion and clamping warnings;
- animated strip dimensions, timing, and the >24-frame fallback;
- invalid property lists and corrupted image data;
- staging cleanup on failure and cancellation;
- atomic commit, duplicate names, preview generation, and reload persistence;
- importing and deleting 20 themes without retained asset directories.

The remaining suites cover schema-v1 decoding, role persistence, preview and
PNG storage, repeated restore state through the system-cursor abstraction, and
idempotent observer lifecycle.

## Manual cursor workflow

1. Apply a theme containing Arrow and Pointing Hand.
2. Confirm Arrow on the desktop and Pointing Hand over links or Finder controls.
3. Confirm I-Beam in an editable text field when the theme provides it.
4. Choose **Restore macOS Cursor**.
5. Confirm the original Arrow, Pointing Hand, and I-Beam return.
6. Repeat Apply → Restore five times.
7. Press Restore three more times.
8. Confirm one responsive cursor, no duplicates, no restart, and no visible lag.

## Resource audit checklist

During a release validation run:

1. Record resident memory after launch and after one warm import.
2. Import and delete 20 synthetic themes.
3. Import several capes, including one animated cape.
4. Apply different themes repeatedly and restore repeatedly.
5. Open/close the hotspot editor and main window.
6. Leave the process running through app activation, display changes, and wake.
7. Record resident memory after an idle settling period.

Expected behavior is bounded fluctuation rather than monotonic growth. The image
cache is intentionally capped; imported image buffers are operation-local;
observers and debounced tasks are cancelled on stop. A clean compiler run alone
is not considered memory-leak evidence.

## 2026-07-25 validation record

Validated on the environment listed in `KNOWN_LIMITATIONS.md`:

- 22 unit tests passed, including the 20-theme import/delete stress test.
- Three real cape themes were imported locally without adding their copyrighted
  assets to the repository. One contained 16 mapped roles, 19 preserved
  unassigned entries, four Arrow scale representations, and two 23-frame
  animations.
- A real imported cape was applied and the system cursor was restored. The
  persisted `activeThemeID` was verified as `null` afterward.
- Apply → Restore was repeated five times earlier in the same validation run;
  Restore alone was repeated three times. There was no duplicate cursor,
  restart requirement, or visible lag.
- The main window was closed while the process remained running, then reopened
  successfully. Imported and pre-existing themes persisted across a full quit
  and relaunch.
- Debug-build RSS was 136,848 KB after launch/warm display and 138,608 KB after
  three real cape imports, theme preview activity, apply/restore, settings, and
  window close/reopen. The 1,760 KB change was bounded during this run; it is
  evidence from this scenario, not a blanket claim that no leak can exist.
- Import staging was empty after completed imports, and the final cursor state
  was restored with no active theme persisted.
