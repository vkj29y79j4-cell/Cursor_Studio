# Cursor Studio Marketplace Architecture

## Scope and principles

Marketplace is an optional, offline-first layer over Cursor Studio's local
library. Applying, restoring, editing, importing, and deleting local cursor
themes never depend on Supabase or an account.

The macOS app contains only:

- the Supabase project URL;
- a Supabase publishable (public/anon) key;
- public bucket names and feature flags.

The app must never contain a `service_role` key, a database password, a JWT
signing secret, or a Storage signing secret. Privileged moderation and signed
download operations belong in trusted server-side functions.

## Apply migrations in this order

1. `Supabase/001_initial_schema.sql`
2. `Supabase/002_storage_policies.sql`
3. `Supabase/003_seed_categories.sql`
4. `Supabase/004_creator_accounts_and_moderation.sql`
5. Create and confirm the first moderator account, then run a customized copy
   of `Supabase/005_bootstrap_first_moderator.example.sql` once.

Run the files in the Supabase SQL editor as a project owner or through the
Supabase CLI migration workflow. Apply them to a staging project before
production.

## Required Supabase resources

The migrations create:

- `public.profiles`;
- marketplace themes, immutable versions, categories, tags, favorites,
  downloads, reports, and moderation records;
- Row Level Security policies;
- a concurrency-safe trigger limiting each creator to five published themes;
- `theme-previews`, a public Storage bucket;
- `theme-packages`, a private Storage bucket.

Supabase Auth is optional for browsing and downloading. Authentication is
required for favorites, reports, creator publishing, and moderation. The
current app implements email/password registration and sign-in. With email
confirmation enabled, registration creates the account and asks the user to
confirm the email before signing in.

## Configuration

The app reads the following values from the bundled
`MarketplaceConfiguration.plist`:

```text
SUPABASE_URL=https://PROJECT_REF.supabase.co
SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
MARKETPLACE_MODE=supabase
```

If the file or values are absent, the app selects `MockMarketplaceService`.
Production configuration should be generated per build configuration. The
public URL and publishable key are safe to ship in a client, but a
`service_role` key, database password, or signing secret must never be added.

## Data model

`themes` is the creator-owned listing. A listing is a `draft`, `published`,
`unlisted`, `suspended`, or `archived`. Only `published` listings appear in
public search. Drafts do not consume publication slots. A database trigger
locks per creator and rejects the sixth transition to `published`, preventing
concurrent requests from bypassing the limit.

`theme_versions` is append-only after publication. Each version records:

- semantic version;
- SHA-256 package checksum;
- exact byte size;
- package and preview Storage paths;
- a validated, non-executable manifest;
- minimum and maximum tested macOS versions;
- compatibility and moderation states.

The client prioritizes compatibility state over ratings. This milestone does
not include reviews or star ratings.

`downloads` stores one minimal event per successful package handoff. Anonymous
events have no IP address, device name, hardware identifier, or raw local
installation identifier. Public aggregate counts are exposed by a view.

`favorites` and `reports` require authentication. Reports and moderation
records are not publicly readable.

## Storage layout

```text
theme-previews/
  {creator-user-id}/{theme-id}/{version-id}/cover.png
  {creator-user-id}/{theme-id}/{version-id}/screenshots/{index}.png

theme-packages/
  {creator-user-id}/{theme-id}/{version-id}/theme.cursorstudio-theme
```

Preview retrieval is public. Upload, update, and delete operations are still
restricted to the owning creator. Theme packages are private; downloads are
authorized by Storage RLS for published versions, or can later be issued as
short-lived signed URLs by a trusted Edge Function.

Creators upload to `{auth.uid()}/{theme-id}/{semantic-version}/...`. Moderators
may read pending private packages solely to validate them before approval.

Published package objects must be treated as immutable. A corrected package is
a new version with a new checksum and path.

## Safe package format

The `.cursorstudio-theme` package is a ZIP container with this exact logical
shape:

```text
manifest.json
Assets/
  arrow.png
  pointingHand.png
  ...
```

`manifest.json` is declarative JSON. It may describe cursor roles, PNG assets,
pixel sizes, hotspots, and a schema version. Listing previews are uploaded
separately to `theme-previews`; they are not trusted as installable assets. The
package
must not contain scripts, executable files, plug-ins, dylibs, shell commands,
URLs to load at install time, or arbitrary file references.

Before extraction, the client validates the ZIP central directory:

- maximum 256 files;
- maximum 64 MiB compressed package;
- maximum 128 MiB total uncompressed content;
- no encrypted entries;
- only Store or Deflate compression;
- no absolute paths, `..`, empty path components, backslashes, control
  characters, or Unicode-normalization collisions;
- no symlinks, hard links, devices, sockets, or executable permission bits;
- no duplicate case-insensitive paths.

Extraction occurs in a fresh directory under `ImportStaging`. The client then
revalidates the extracted tree, accepts only `manifest.json` and PNG assets,
decodes every image with ImageIO, enforces pixel and frame limits, verifies all
manifest references and the SHA-256 checksum, and commits by an atomic move.
Failures and cancellations delete staging data and do not alter the library.

## Client architecture

The UI depends only on:

```swift
protocol MarketplaceServing {
    func featuredThemes() async throws -> [MarketplaceTheme]
    func searchThemes(
        query: String,
        filters: MarketplaceFilters
    ) async throws -> [MarketplaceTheme]
    func themeDetails(id: UUID) async throws -> MarketplaceThemeDetails
    func downloadTheme(id: UUID) async throws -> URL
}
```

Implementations:

- `MockMarketplaceService`: bundled deterministic catalog and locally generated
  safe packages. It makes Marketplace usable with no backend or network.
- `SupabaseMarketplaceService`: REST/Auth/Storage implementation activated only
  when public configuration is valid.
- `CachedMarketplaceService`: bounded disk and memory caching around either
  implementation.

Models used by Marketplace are separate from local `CursorTheme` persistence
models. A validated installer is the only conversion boundary.

## Offline and failure behavior

- Local Library is always available.
- The last successful Marketplace response is cached with a timestamp.
- Image cache is bounded by item count and total bytes.
- Search is debounced and cancellable.
- Downloads expose progress, cancel, retry, and clear failure states.
- When the network is absent, cached results are shown with an offline badge.
- An incomplete download or invalid package is never offered to the local
  library.

## Publication and moderation flow

1. The creator registers or signs in. Access and rotating refresh tokens are
   stored in the app-scoped macOS Data Protection Keychain, never in
   preferences or logs. Cursor Studio does not query the legacy file-based
   Keychain, avoiding its access-control prompt after app updates or re-signing.
   Unsigned local development builds, which have no signing access group, use
   an application-support session file restricted to the current user
   (`0700` directory and `0600` file). A signed build migrates that fallback
   into its private Data Protection Keychain automatically.
2. The app packages a selected local theme, validates the resulting ZIP and
   checksum, creates a draft listing, and uploads preview/package objects to
   creator-owned Storage paths.
3. The client inserts an immutable draft version and calls
   `submit_theme_version`; the database permits only the owner transition
   `draft -> pending`.
4. A moderator opens the queue. Before approval, the moderator client
   downloads the private package and repeats ZIP, image, manifest, theme-id,
   semantic-version, and SHA-256 validation. The validated package is installed
   into an isolated temporary library and applied on the moderator's Mac for
   visual testing; approval remains disabled until that test succeeds. Stopping
   the test restores the previously active cursor and removes the temporary
   library.
5. `moderate_theme_version` atomically records the decision. Approval updates
   the current version and publishes the listing; the database rejects a sixth
   published theme for the same creator. Rejection keeps the listing private.
6. Moderator membership is stored only in `app_private.moderators`.
   `set_marketplace_moderator` requires an existing moderator and refuses to
   remove the final moderator. The first moderator is bootstrapped once in the
   SQL editor.
7. Reports enter the moderation queue. Moderators can suspend a listing and
   record an auditable action.

Client-side validation improves feedback but never replaces server-side
validation or RLS.

## Production checklist

- Enable leaked-password protection and appropriate Auth rate limits.
- Keep email confirmation enabled and configure the production site/redirect
  URLs before accepting registrations.
- Require MFA for moderator accounts.
- Add CAPTCHA/rate limiting to anonymous download RPCs if abused.
- Validate packages in an isolated Edge Function or worker before approval.
- Set Storage file-size and MIME restrictions in the dashboard as defense in
  depth.
- Back up Postgres and define retention for reports and download events.
- Add monitoring for failed RLS checks, package validation, and publication
  slot rejections without logging cursor files or personal data.
- Review `Docs/PrivacyPolicyDraft.md` with counsel before launch.
