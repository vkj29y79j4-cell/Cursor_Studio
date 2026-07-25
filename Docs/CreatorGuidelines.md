# Cursor Studio Creator Guidelines

## Before publishing

- Confirm that you own or may redistribute every asset.
- Test all provided roles on the minimum and maximum macOS versions you claim.
- Keep hotspots inside image bounds.
- Prefer transparent PNGs with crisp 1× and 2× representations.
- Check the theme in light and dark appearances and with increased cursor size.
- Provide a clear preview and disclose animated roles and static fallbacks.

## Package requirements

Publish only the declarative `.cursorstudio-theme` package described in
`Docs/MarketplaceArchitecture.md`. Do not add scripts, executables, aliases,
symlinks, remote resources, hidden files, or unrelated metadata. Published
versions are immutable; upload a new semantic version for every correction.

## Publication slots

Each creator may have at most five `published` listings at once. Draft,
archived, and suspended listings do not consume a slot. Unpublish or archive a
listing before publishing another. Creating extra accounts to avoid this limit
is prohibited.

## Updates

Use semantic versions. Explain visible changes and compatibility changes.
Never replace an existing package object in Storage. A new package must have a
new version record, path, and SHA-256 checksum.

## Privacy

Do not place names, emails, device identifiers, file paths, or other personal
data inside theme assets or metadata unless the person has clearly consented
and the information is necessary for attribution.
