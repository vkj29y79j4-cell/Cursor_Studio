# Cursor Studio Privacy Policy — Draft

> Draft for product and legal review. This is not final legal advice.

## Local application data

Cursor Studio stores the local theme library, copied cursor images,
preferences, and a bounded diagnostic log on the user's Mac. Local editing,
importing, applying, and restoring do not require an account or a network
connection. Cursor Studio does not include product analytics in this milestone.

## Marketplace browsing

Marketplace requests may expose standard network information such as an IP
address to the hosting provider, Supabase, and infrastructure logs. The public
catalog returns listings, previews, compatibility metadata, and aggregate
download counts. Cursor Studio does not intentionally send local cursor
libraries while browsing.

## Accounts

If a user chooses to sign in, Supabase Auth processes the selected sign-in
email address, password authentication records, session identifiers, and
rotating access/refresh tokens. Cursor Studio stores session tokens in the
app-scoped macOS Data Protection Keychain. Unsigned local development builds
use a current-user-only Application Support file instead. It does not store the
password. An account is required
only for favorites, reports, creator publishing, and moderation.

## Publishing

When a creator publishes, Cursor Studio uploads the submitted theme package,
preview images, listing metadata, compatibility information, and creator
profile data after an explicit confirmation action. Published listing data is
public. Packages are stored privately but are downloadable for published
versions through controlled access. Authorized moderators can download pending
packages for security and compatibility validation.

## Favorites, reports, and downloads

Favorites are associated with the signed-in account. Reports contain the
selected reason, optional details, timestamps, and moderation status. Download
events record the theme/version, timestamp, and signed-in user identifier when
available. The planned schema does not store a raw IP address, hardware
identifier, device name, or local library identifier in download records.

## Retention and deletion

Local themes can be deleted in the app. Account, favorite, report, and
published-content deletion workflows must be completed before production.
Security, fraud, moderation, backup, or legal obligations may require limited
retention; final periods must be documented here before launch.

## Service providers and transfers

Supabase provides authentication, Postgres, and file storage. The production
policy must identify the selected Supabase region, other infrastructure
providers, subprocessors, and any international data transfers.

## User choices

Users may use the local library without Marketplace or an account. Marketplace
features should explain when sign-in is required. The production app must
provide support contact details for access, correction, export, and deletion
requests.

## Security and children

The service uses access policies, private package storage, bounded package
validation, and least-privilege public credentials. No security measure is
perfect. The production policy must state the intended age audience and any
regional parental-consent requirements.
