# Known limitations

## Private macOS APIs

Cursor Studio uses unsupported WindowServer/CoreGraphics cursor registration
symbols loaded at runtime. Apple can rename, remove, or change them in any macOS
update. The app is therefore not suitable for the Mac App Store, and each major
macOS release needs the validation workflow in
`Documentation/PRIVATE_CURSOR_API.md`.

The current source build has App Sandbox and hardened runtime disabled. It does
not request root or Accessibility access, change SIP, install a daemon, or
modify protected system files.

## Mousecape import

- XML and binary property-list capes using the documented Mousecape dictionary
  fields are supported.
- NSKeyedArchive and unknown archive layouts are rejected.
- Known cursor identifiers are mapped to Cursor Studio's 17 roles. Unknown and
  duplicate mappings are preserved as unassigned metadata but are not applied.
- The importer reads PNG-compatible image representations. Other representation
  encodings accepted by some historical Mousecape versions may be rejected.
- Malformed individual cursors become review warnings where the rest of the
  theme remains usable.
- Cursor Studio imports a copy of every required asset; it does not track later
  changes to the original cape.

## Animated cursors

Vertically stacked animation strips preserve frame order, count, point size,
Retina scale, and duration. Up to 24 frames are sent to the current private API.
Animations above 24 frames retain their original strips and metadata but apply
the extracted first frame; the editor and import review mark this fallback.

## Windows cursor import

- PNG-backed and classic DIB-backed `.cur` representations are decoded through
  ImageIO, with hotspots and multi-resolution data preserved.
- RIFF ACON `.ani` files are supported when frames contain standard CUR/ICO
  chunks. Variable frame timing is normalized to one average duration because
  the macOS registration API exposes one duration.
- Windows `.inf` scheme roles and common filenames are recognized. Windows-only
  roles without a macOS equivalent remain visible as unassigned entries.
- ZIP import rejects traversal paths, links, devices, encryption, unsupported
  compression, excessive file counts, and oversized expanded archives.

## Application compatibility

Replacement is global at the WindowServer registration level, but an
application can draw its own pointer, cache a private cursor, or reset a
registration. Such cursors may not follow the theme until a relevant system
notification or application activation triggers a reapply. Games, remote
desktop/virtualization software, secure system surfaces, and apps with custom
rendered cursors are the most likely exceptions.

## Helper and login behavior

There is no privileged helper or LaunchAgent. The optional `SMAppService` login
item launches the main app, which first removes stale custom registrations.
Closing only the main window can leave Cursor Studio running and its
event-driven monitor active, depending on the user's setting.

## Tested environment

The current implementation was built and manually validated on:

- macOS 26.5.2 (25F84)
- Apple Silicon
- Xcode 26.6 (17F113), Swift 6.3.3

The deployment target is macOS 15.0, but private-API behavior must be verified
on each actual OS version before relying on it.
