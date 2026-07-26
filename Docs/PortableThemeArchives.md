# Portable Cursor Studio themes

Cursor Studio 1.9 can export any configured local theme as a
`.cursorstudio-theme` file. The format is intended for backups, sharing between
Macs, and moving work between a creator's local library and Marketplace without
flattening cursor metadata.

## User flow

1. Select a non-empty theme in Library.
2. Choose **Export Theme…** in the toolbar, theme context menu, or File menu.
3. Save the package anywhere in Finder.
4. Import the package through the existing Import command or drag it into the
   app.
5. Review every recognized role and animation before committing it.

Import never overwrites an existing theme. Cursor Studio assigns a new local
identifier and resolves duplicate display names using the same transaction as
Mousecape and Windows imports.

## Package contents

The archive is a ZIP file with a dedicated extension:

```text
manifest.json
Assets/
  arrow.png
  arrow-representation-1.png
  ...
```

Schema version 1 stores the theme identifier and name, semantic package
version, optional author and export time, and one declarative record per cursor
role. Each record includes:

- source pixel and point dimensions;
- normalized hotspot coordinates;
- animation frame count and duration;
- an explicit static-fallback marker;
- zero or more scale-specific representations.

The base asset remains a single-frame PNG. Animation strips are stored as
representations, matching the internal Mousecape, Windows ANI, and Marketplace
model.

## Validation and safety

Portable archives deliberately use `MarketplacePackageBuilder`,
`MarketplacePackageValidator`, and the common `MarketplaceInstaller` draft
converter. This keeps local sharing and downloaded Marketplace themes on one
security boundary.

Before a package reaches the review sheet, Cursor Studio verifies:

- archive and expanded-size limits;
- file-count and manifest-schema limits;
- normalized relative paths with no traversal;
- absence of symbolic links and unsupported file types;
- SHA-256 when an expected digest is supplied by Marketplace;
- PNG type, dimensions, frame structure, and decodability;
- known cursor roles, finite hotspots, point sizes, and representations.

The validated package is copied into an isolated staging directory. It is moved
into the local library only after the user confirms the review; cancelling or a
failed commit removes staging data.

## Compatibility

The two optional manifest fields added in 1.9 (`author` and `exportedAt`) do not
change the schema version. Older schema-v1 Marketplace packages decode without
them, while current Cursor Studio builds preserve them when present.
