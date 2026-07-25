begin;

-- Preserve the requested creator handle when it is available. A short user-id
-- suffix is added only when another profile already owns that handle.
create or replace function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested_handle text;
  resolved_handle text;
begin
  requested_handle := lower(
    regexp_replace(
      coalesce(new.raw_user_meta_data ->> 'preferred_username', 'creator'),
      '[^a-zA-Z0-9_-]',
      '',
      'g'
    )
  );
  if requested_handle !~ '^[a-z0-9][a-z0-9_-]{2,31}$' then
    requested_handle := 'creator';
  end if;

  resolved_handle := left(requested_handle, 32);
  if exists (
    select 1 from public.profiles where handle = resolved_handle
  ) then
    resolved_handle :=
      left(requested_handle, 23)
      || '-'
      || left(replace(new.id::text, '-', ''), 8);
  end if;

  insert into public.profiles (id, handle, display_name)
  values (
    new.id,
    resolved_handle,
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

-- Creators may make the single safe review transition draft -> pending.
-- Moderators retain control over approval, rejection, and compatibility.
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

    if old.review_status = 'draft'
       and new.review_status = 'pending'
       and current_setting(
         'cursor_studio.submitting_version',
         true
       ) = old.id::text then
      new.review_status := 'pending';
    else
      new.review_status := old.review_status;
    end if;

    new.compatibility := old.compatibility;
    new.approved_at := old.approved_at;

    if old.review_status <> 'draft' then
      new.package_path := old.package_path;
      new.package_sha256 := old.package_sha256;
      new.package_bytes := old.package_bytes;
      new.preview_paths := old.preview_paths;
      new.manifest := old.manifest;
      new.minimum_macos_major := old.minimum_macos_major;
      new.maximum_tested_macos_major := old.maximum_tested_macos_major;
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.submit_theme_version(
  requested_version_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested_user_id uuid := (select auth.uid());
  requested_theme_id uuid;
  stored_package_path text;
  stored_preview_paths jsonb;
begin
  if requested_user_id is null then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'Authentication is required.';
  end if;

  select v.theme_id, v.package_path, v.preview_paths
    into requested_theme_id, stored_package_path, stored_preview_paths
    from public.theme_versions v
    join public.themes t on t.id = v.theme_id
   where v.id = requested_version_id
     and v.review_status = 'draft'
     and t.owner_id = requested_user_id
   for update of v;

  if requested_theme_id is null then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'Only the owner may submit a draft version.';
  end if;

  if stored_package_path not like (
      requested_user_id::text
      || '/'
      || requested_theme_id::text
      || '/%'
    )
    or jsonb_array_length(stored_preview_paths) < 1
    or exists (
      select 1
      from jsonb_array_elements_text(stored_preview_paths) as preview(path)
      where preview.path not like (
        requested_user_id::text
        || '/'
        || requested_theme_id::text
        || '/%'
      )
    )
    or not exists (
      select 1
      from storage.objects o
      where o.bucket_id = 'theme-packages'
        and o.name = stored_package_path
    )
    or exists (
      select 1
      from jsonb_array_elements_text(stored_preview_paths) as preview(path)
      where not exists (
        select 1
        from storage.objects o
        where o.bucket_id = 'theme-previews'
          and o.name = preview.path
      )
    ) then
    raise exception using
      errcode = 'check_violation',
      message = 'Package and preview paths must belong to the creator and theme.';
  end if;

  perform set_config(
    'cursor_studio.submitting_version',
    requested_version_id::text,
    true
  );

  update public.theme_versions
     set review_status = 'pending'
   where id = requested_version_id;
end;
$$;

revoke all on function public.submit_theme_version(uuid) from public;
grant execute on function public.submit_theme_version(uuid) to authenticated;

create or replace function public.moderate_theme_version(
  requested_version_id uuid,
  decision text,
  compatibility_result text,
  note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested_theme_id uuid;
  result_compatibility public.compatibility_status;
begin
  if not public.is_marketplace_moderator() then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'Moderator access is required.';
  end if;

  if decision not in ('approved', 'rejected') then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'Decision must be approved or rejected.';
  end if;

  begin
    result_compatibility := compatibility_result::public.compatibility_status;
  exception when invalid_text_representation then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'Compatibility result is invalid.';
  end;

  select theme_id
    into requested_theme_id
    from public.theme_versions
   where id = requested_version_id
     and review_status = 'pending'
   for update;

  if requested_theme_id is null then
    raise exception using
      errcode = 'no_data_found',
      message = 'The pending version no longer exists.';
  end if;

  if decision = 'approved' then
    update public.theme_versions
       set review_status = 'approved',
           compatibility = result_compatibility,
           approved_at = now()
     where id = requested_version_id;

    update public.themes
       set current_version_id = requested_version_id,
           publication_status = 'published'
     where id = requested_theme_id;
  else
    update public.theme_versions
       set review_status = 'rejected',
           compatibility = result_compatibility,
           approved_at = null
     where id = requested_version_id;
  end if;

  insert into public.moderation_actions (
    moderator_id,
    theme_id,
    version_id,
    action,
    note
  )
  values (
    (select auth.uid()),
    requested_theme_id,
    requested_version_id,
    case
      when decision = 'approved' then 'approve_version'
      else 'reject_version'
    end,
    nullif(left(coalesce(note, ''), 4000), '')
  );
end;
$$;

revoke all on function public.moderate_theme_version(uuid, text, text, text)
  from public;
grant execute on function public.moderate_theme_version(
  uuid,
  text,
  text,
  text
) to authenticated;

create or replace function public.list_marketplace_moderators()
returns table (
  id uuid,
  handle text,
  display_name text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_marketplace_moderator() then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'Moderator access is required.';
  end if;

  return query
  select p.id, p.handle, p.display_name
    from app_private.moderators m
    join public.profiles p on p.id = m.user_id
   order by p.handle;
end;
$$;

revoke all on function public.list_marketplace_moderators() from public;
grant execute on function public.list_marketplace_moderators()
  to authenticated;

create or replace function public.set_marketplace_moderator(
  requested_handle text,
  enabled boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested_user_id uuid;
  moderator_count integer;
begin
  if not public.is_marketplace_moderator() then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'Moderator access is required.';
  end if;

  select id
    into requested_user_id
    from public.profiles
   where handle = lower(trim(requested_handle));

  if requested_user_id is null then
    raise exception using
      errcode = 'no_data_found',
      message = 'Creator profile not found.';
  end if;

  if enabled then
    insert into app_private.moderators (user_id)
    values (requested_user_id)
    on conflict (user_id) do nothing;
  else
    select count(*) into moderator_count
      from app_private.moderators;
    if moderator_count <= 1 then
      raise exception using
        errcode = 'check_violation',
        message = 'The last moderator cannot be removed.';
    end if;
    delete from app_private.moderators
     where user_id = requested_user_id;
  end if;
end;
$$;

revoke all on function public.set_marketplace_moderator(text, boolean)
  from public;
grant execute on function public.set_marketplace_moderator(text, boolean)
  to authenticated;

-- The public bucket bypasses SELECT checks for serving objects, but Storage
-- requires SELECT in addition to DELETE when creators remove failed uploads.
drop policy if exists preview_creator_select on storage.objects;
create policy preview_creator_select
on storage.objects for select
to authenticated
using (
  bucket_id = 'theme-previews'
  and owner_id = (select auth.uid()::text)
  and public.creator_owns_storage_theme(name)
);

drop policy if exists package_published_or_owner_read on storage.objects;
drop policy if exists package_published_owner_or_moderator_read
  on storage.objects;
create policy package_published_owner_or_moderator_read
on storage.objects for select
to anon, authenticated
using (
  bucket_id = 'theme-packages'
  and (
    public.storage_object_is_published_package(name)
    or (
      (select auth.uid()) is not null
      and owner_id = (select auth.uid()::text)
      and public.creator_owns_storage_theme(name)
    )
    or public.is_marketplace_moderator()
  )
);

commit;
