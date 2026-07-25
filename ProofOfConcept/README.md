# Global Arrow proof of concept

This small executable validates the technical prerequisite for Cursor Studio:
it registers a real global WindowServer Arrow cursor, verifies that the global
registration contains the generated image and hotspot, keeps it visible briefly,
and restores macOS system cursors.

It does not create an overlay, poll the pointer, hide the cursor, or use
Accessibility APIs.

Build and run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun swiftc ProofOfConcept/SystemCursorProof.swift \
  -framework ApplicationServices -framework CoreGraphics \
  -o /tmp/cursor-studio-system-cursor-proof

/tmp/cursor-studio-system-cursor-proof 8
```

The optional argument is the number of seconds to keep the proof cursor active
(clamped to 1–60). The program restores defaults using
`CoreCursorUnregisterAll` and `CoreCursorSet`, including on verification failure.
