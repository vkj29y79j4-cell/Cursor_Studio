begin;

create extension if not exists pgcrypto with schema extensions;

create type public.theme_publication_status as enum (
  'draft',
  'published',
  'unlisted',
  'suspended',
  'archived'
);

create type public.version_review_status as enum (
  'draft',
  'pending',
  'approved',
  'rejected'
);

create type public.compatibility_status as enum (
  'unknown',
  'compatible',
  'limited',
  'incompatible'
);

create type public.report_status as enum (
  'open',
  'reviewing',
  'resolved',
  'dismissed'
);

create schema if not exists app_private;
revoke all on schema app_private from public, anon, authenticated;

create table app_private.moderators (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  handle text not null unique
    check (handle ~ '^[a-z0-9][a-z0-9_-]{2,31}$'),
  display_name text not null
    check (char_length(display_name) between 1 and 80),
  avatar_path text,
  bio text check (bio is null or char_length(bio) <= 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9-]{2,50}$'),
  name_en text not null check (char_length(name_en) between 1 and 60),
  name_ru text not null check (char_length(name_ru) between 1 and 60),
  sort_order integer not null default 0,
  is_active boolean not null default true
);

create table public.tags (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9-]{2,50}$'),
  name_en text not null check (char_length(name_en) between 1 and 60),
  name_ru text not null check (char_length(name_ru) between 1 and 60),
  is_active boolean not null default true
);

create table public.themes (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  slug text not null check (slug ~ '^[a-z0-9][a-z0-9-]{2,79}$'),
  title_en text not null check (char_length(title_en) between 1 and 100),
  title_ru text check (title_ru is null or char_length(title_ru) between 1 and 100),
  description_en text not null
    check (char_length(description_en) between 1 and 4000),
  description_ru text
    check (description_ru is null or char_length(description_ru) between 1 and 4000),
  category_id uuid references public.categories(id) on delete set null,
  publication_status public.theme_publication_status not null default 'draft',
  is_verified boolean not null default false,
  is_featured boolean not null default false,
  current_version_id uuid,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_id, slug)
);

create table public.theme_versions (
  id uuid primary key default gen_random_uuid(),
  theme_id uuid not null references public.themes(id) on delete cascade,
  semantic_version text not null
    check (semantic_version ~ '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)([-+][0-9A-Za-z.-]+)?$'),
  package_path text not null unique,
  package_sha256 text not null check (package_sha256 ~ '^[a-f0-9]{64}$'),
  package_bytes bigint not null check (package_bytes between 1 and 67108864),
  preview_paths jsonb not null default '[]'::jsonb
    check (jsonb_typeof(preview_paths) = 'array'),
  manifest jsonb not null check (jsonb_typeof(manifest) = 'object'),
  minimum_macos_major integer not null default 15
    check (minimum_macos_major between 15 and 99),
  maximum_tested_macos_major integer
    check (
      maximum_tested_macos_major is null
      or maximum_tested_macos_major >= minimum_macos_major
    ),
  compatibility public.compatibility_status not null default 'unknown',
  review_status public.version_review_status not null default 'draft',
  release_notes_en text check (
    release_notes_en is null or char_length(release_notes_en) <= 4000
  ),
  release_notes_ru text check (
    release_notes_ru is null or char_length(release_notes_ru) <= 4000
  ),
  created_at timestamptz not null default now(),
  approved_at timestamptz,
  unique (theme_id, semantic_version)
);

alter table public.themes
  add constraint themes_current_version_fk
  foreign key (current_version_id)
  references public.theme_versions(id)
  on delete set null
  deferrable initially deferred;

create table public.theme_tags (
  theme_id uuid not null references public.themes(id) on delete cascade,
  tag_id uuid not null references public.tags(id) on delete cascade,
  primary key (theme_id, tag_id)
);

create table public.favorites (
  user_id uuid not null references public.profiles(id) on delete cascade,
  theme_id uuid not null references public.themes(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, theme_id)
);

create table public.downloads (
  id bigint generated always as identity primary key,
  theme_id uuid not null references public.themes(id) on delete cascade,
  version_id uuid not null references public.theme_versions(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  theme_id uuid not null references public.themes(id) on delete cascade,
  reason text not null check (
    reason in (
      'copyright',
      'malware',
      'misleading',
      'harassment',
      'privacy',
      'other'
    )
  ),
  details text check (details is null or char_length(details) <= 4000),
  status public.report_status not null default 'open',
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create table public.moderation_actions (
  id uuid primary key default gen_random_uuid(),
  moderator_id uuid not null references auth.users(id) on delete restrict,
  theme_id uuid references public.themes(id) on delete set null,
  version_id uuid references public.theme_versions(id) on delete set null,
  report_id uuid references public.reports(id) on delete set null,
  action text not null check (
    action in (
      'approve_version',
      'reject_version',
      'verify_creator',
      'feature_theme',
      'unfeature_theme',
      'suspend_theme',
      'restore_theme',
      'resolve_report'
    )
  ),
  note text check (note is null or char_length(note) <= 4000),
  created_at timestamptz not null default now()
);

create index themes_public_catalog_idx
  on public.themes (publication_status, is_featured desc, published_at desc);
create index themes_owner_idx on public.themes (owner_id, publication_status);
create index theme_versions_theme_idx
  on public.theme_versions (theme_id, created_at desc);
create index downloads_theme_idx on public.downloads (theme_id, created_at desc);
create index reports_status_idx on public.reports (status, created_at);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create trigger themes_set_updated_at
before update on public.themes
for each row execute function public.set_updated_at();

create or replace function public.is_marketplace_moderator()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from app_private.moderators
    where user_id = (select auth.uid())
  );
$$;

revoke all on function public.is_marketplace_moderator() from public;
grant execute on function public.is_marketplace_moderator() to anon, authenticated;

create or replace function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  base_handle text;
begin
  base_handle := lower(
    regexp_replace(
      coalesce(new.raw_user_meta_data ->> 'preferred_username', 'creator'),
      '[^a-zA-Z0-9_-]',
      '',
      'g'
    )
  );
  if char_length(base_handle) < 3 then
    base_handle := 'creator';
  end if;

  insert into public.profiles (id, handle, display_name)
  values (
    new.id,
    left(base_handle, 23) || '-' || left(replace(new.id::text, '-', ''), 8),
    left(
      coalesce(
        nullif(new.raw_user_meta_data ->> 'full_name', ''),
        nullif(new.raw_user_meta_data ->> 'name', ''),
        'Cursor Creator'
      ),
      80
    )
  );
  return new;
end;
$$;

create trigger auth_user_created_create_profile
after insert on auth.users
for each row execute function public.create_profile_for_new_user();

create or replace function public.protect_theme_moderation_fields()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.is_verified := false;
    new.is_featured := false;
  elsif not public.is_marketplace_moderator() then
    new.is_verified := old.is_verified;
    new.is_featured := old.is_featured;
    if old.publication_status = 'suspended' then
      new.publication_status := old.publication_status;
    end if;
  end if;
  return new;
end;
$$;

create trigger themes_protect_moderation_fields
before insert or update on public.themes
for each row execute function public.protect_theme_moderation_fields();

create or replace function public.protect_version_review_fields()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.review_status := 'draft';
    new.compatibility := 'unknown';
    new.approved_at := null;
  elsif not public.is_marketplace_moderator() then
    if old.review_status = 'approved' then
      raise exception using
        errcode = 'insufficient_privilege',
        message = 'Approved versions are immutable; create a new version.';
    end if;
    new.review_status := old.review_status;
    new.compatibility := old.compatibility;
    new.approved_at := old.approved_at;
    new.package_path := old.package_path;
    new.package_sha256 := old.package_sha256;
    new.package_bytes := old.package_bytes;
    new.manifest := old.manifest;
  end if;
  return new;
end;
$$;

create trigger theme_versions_protect_review_fields
before insert or update on public.theme_versions
for each row execute function public.protect_version_review_fields();

create or replace function public.enforce_publication_requirements()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  published_count integer;
begin
  if new.publication_status = 'published'
     and (
       tg_op = 'INSERT'
       or old.publication_status is distinct from 'published'
       or old.current_version_id is distinct from new.current_version_id
     ) then
    perform pg_advisory_xact_lock(
      hashtextextended(new.owner_id::text, 128947)
    );

    if new.current_version_id is null or not exists (
      select 1
      from public.theme_versions v
      where v.id = new.current_version_id
        and v.theme_id = new.id
        and v.review_status = 'approved'
    ) then
      raise exception using
        errcode = 'check_violation',
        message = 'An approved current version is required before publication.';
    end if;

    select count(*)
      into published_count
      from public.themes t
     where t.owner_id = new.owner_id
       and t.publication_status = 'published'
       and t.id <> new.id;

    if published_count >= 5 then
      raise exception using
        errcode = 'check_violation',
        message = 'A creator may have at most five published themes.';
    end if;

    if new.published_at is null then
      new.published_at := now();
    end if;
  end if;

  return new;
end;
$$;

create trigger themes_enforce_publication_requirements
before insert or update of publication_status, current_version_id
on public.themes
for each row execute function public.enforce_publication_requirements();

create or replace function public.record_theme_download(
  requested_theme_id uuid,
  requested_version_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.themes t
    join public.theme_versions v on v.id = requested_version_id
    where t.id = requested_theme_id
      and t.publication_status = 'published'
      and t.current_version_id = v.id
      and v.theme_id = t.id
      and v.review_status = 'approved'
  ) then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'The requested published version is unavailable.';
  end if;

  insert into public.downloads (theme_id, version_id, user_id)
  values (requested_theme_id, requested_version_id, (select auth.uid()));
end;
$$;

revoke all on function public.record_theme_download(uuid, uuid) from public;
grant execute on function public.record_theme_download(uuid, uuid)
  to anon, authenticated;

create view public.theme_download_counts
with (security_barrier = true)
as
select theme_id, count(*)::bigint as download_count
from public.downloads
group by theme_id;

alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.tags enable row level security;
alter table public.themes enable row level security;
alter table public.theme_versions enable row level security;
alter table public.theme_tags enable row level security;
alter table public.favorites enable row level security;
alter table public.downloads enable row level security;
alter table public.reports enable row level security;
alter table public.moderation_actions enable row level security;

create policy profiles_public_read
on public.profiles for select
to anon, authenticated
using (true);

create policy profiles_owner_update
on public.profiles for update
to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

create policy categories_public_read
on public.categories for select
to anon, authenticated
using (is_active or public.is_marketplace_moderator());

create policy tags_public_read
on public.tags for select
to anon, authenticated
using (is_active or public.is_marketplace_moderator());

create policy themes_catalog_read
on public.themes for select
to anon, authenticated
using (
  publication_status = 'published'
  or owner_id = (select auth.uid())
  or public.is_marketplace_moderator()
);

create policy themes_owner_insert
on public.themes for insert
to authenticated
with check (owner_id = (select auth.uid()));

create policy themes_owner_update
on public.themes for update
to authenticated
using (
  owner_id = (select auth.uid())
  or public.is_marketplace_moderator()
)
with check (
  owner_id = (select auth.uid())
  or public.is_marketplace_moderator()
);

create policy themes_owner_delete
on public.themes for delete
to authenticated
using (
  owner_id = (select auth.uid())
  or public.is_marketplace_moderator()
);

create policy versions_catalog_read
on public.theme_versions for select
to anon, authenticated
using (
  exists (
    select 1
    from public.themes t
    where t.id = theme_id
      and (
        (t.publication_status = 'published' and review_status = 'approved')
        or t.owner_id = (select auth.uid())
        or public.is_marketplace_moderator()
      )
  )
);

create policy versions_owner_insert
on public.theme_versions for insert
to authenticated
with check (
  exists (
    select 1 from public.themes t
    where t.id = theme_id
      and t.owner_id = (select auth.uid())
  )
);

create policy versions_owner_update
on public.theme_versions for update
to authenticated
using (
  exists (
    select 1 from public.themes t
    where t.id = theme_id
      and (
        t.owner_id = (select auth.uid())
        or public.is_marketplace_moderator()
      )
  )
)
with check (
  exists (
    select 1 from public.themes t
    where t.id = theme_id
      and (
        t.owner_id = (select auth.uid())
        or public.is_marketplace_moderator()
      )
  )
);

create policy versions_owner_delete_drafts
on public.theme_versions for delete
to authenticated
using (
  review_status = 'draft'
  and exists (
    select 1 from public.themes t
    where t.id = theme_id
      and t.owner_id = (select auth.uid())
  )
);

create policy theme_tags_catalog_read
on public.theme_tags for select
to anon, authenticated
using (
  exists (
    select 1 from public.themes t
    where t.id = theme_id
      and (
        t.publication_status = 'published'
        or t.owner_id = (select auth.uid())
        or public.is_marketplace_moderator()
      )
  )
);

create policy theme_tags_owner_write
on public.theme_tags for all
to authenticated
using (
  exists (
    select 1 from public.themes t
    where t.id = theme_id
      and t.owner_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1 from public.themes t
    where t.id = theme_id
      and t.owner_id = (select auth.uid())
  )
);

create policy favorites_owner_read
on public.favorites for select
to authenticated
using (user_id = (select auth.uid()));

create policy favorites_owner_insert
on public.favorites for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and exists (
    select 1 from public.themes t
    where t.id = theme_id and t.publication_status = 'published'
  )
);

create policy favorites_owner_delete
on public.favorites for delete
to authenticated
using (user_id = (select auth.uid()));

create policy downloads_aggregate_read
on public.downloads for select
to anon, authenticated
using (
  exists (
    select 1 from public.themes t
    where t.id = theme_id and t.publication_status = 'published'
  )
);

create policy reports_owner_insert
on public.reports for insert
to authenticated
with check (
  reporter_id = (select auth.uid())
  and status = 'open'
  and exists (
    select 1 from public.themes t
    where t.id = theme_id and t.publication_status = 'published'
  )
);

create policy reports_owner_or_moderator_read
on public.reports for select
to authenticated
using (
  reporter_id = (select auth.uid())
  or public.is_marketplace_moderator()
);

create policy reports_moderator_update
on public.reports for update
to authenticated
using (public.is_marketplace_moderator())
with check (public.is_marketplace_moderator());

create policy moderation_actions_moderator_read
on public.moderation_actions for select
to authenticated
using (public.is_marketplace_moderator());

create policy moderation_actions_moderator_insert
on public.moderation_actions for insert
to authenticated
with check (
  public.is_marketplace_moderator()
  and moderator_id = (select auth.uid())
);

grant usage on schema public to anon, authenticated;
grant select on public.profiles, public.categories, public.tags,
  public.themes, public.theme_versions, public.theme_tags,
  public.theme_download_counts to anon, authenticated;
grant select, insert, update, delete on public.themes,
  public.theme_versions, public.theme_tags to authenticated;
grant select, insert, delete on public.favorites to authenticated;
grant select, insert, update on public.reports to authenticated;
grant select, insert on public.moderation_actions to authenticated;
revoke all on public.downloads from anon, authenticated;
revoke all on sequence public.downloads_id_seq from anon, authenticated;
revoke insert, update, delete on public.categories, public.tags
  from anon, authenticated;

commit;
