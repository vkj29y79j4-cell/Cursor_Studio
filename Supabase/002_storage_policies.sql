begin;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values
  (
    'theme-previews',
    'theme-previews',
    true,
    10485760,
    array['image/png']
  ),
  (
    'theme-packages',
    'theme-packages',
    false,
    67108864,
    array['application/zip', 'application/octet-stream']
  )
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.creator_owns_storage_theme(object_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    (storage.foldername(object_name))[1] = (select auth.uid())::text
    and exists (
      select 1
      from public.themes t
      where t.owner_id = (select auth.uid())
        and t.id::text = (storage.foldername(object_name))[2]
    );
$$;

revoke all on function public.creator_owns_storage_theme(text) from public;
grant execute on function public.creator_owns_storage_theme(text)
  to authenticated;

create or replace function public.storage_object_is_published_package(
  object_name text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.theme_versions v
    join public.themes t on t.id = v.theme_id
    where v.package_path = object_name
      and v.review_status = 'approved'
      and t.publication_status = 'published'
      and t.current_version_id = v.id
  );
$$;

revoke all on function public.storage_object_is_published_package(text)
  from public;
grant execute on function public.storage_object_is_published_package(text)
  to anon, authenticated;

create policy preview_creator_insert
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'theme-previews'
  and public.creator_owns_storage_theme(name)
  and (storage.extension(name)) = 'png'
);

create policy preview_creator_update
on storage.objects for update
to authenticated
using (
  bucket_id = 'theme-previews'
  and owner_id = (select auth.uid()::text)
  and public.creator_owns_storage_theme(name)
)
with check (
  bucket_id = 'theme-previews'
  and owner_id = (select auth.uid()::text)
  and public.creator_owns_storage_theme(name)
  and (storage.extension(name)) = 'png'
);

create policy preview_creator_delete
on storage.objects for delete
to authenticated
using (
  bucket_id = 'theme-previews'
  and owner_id = (select auth.uid()::text)
  and public.creator_owns_storage_theme(name)
);

create policy package_published_or_owner_read
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
  )
);

create policy package_creator_insert
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'theme-packages'
  and public.creator_owns_storage_theme(name)
  and (storage.extension(name)) = 'cursorstudio-theme'
);

create policy package_creator_delete_unpublished
on storage.objects for delete
to authenticated
using (
  bucket_id = 'theme-packages'
  and owner_id = (select auth.uid()::text)
  and public.creator_owns_storage_theme(name)
  and not public.storage_object_is_published_package(name)
);

-- There is deliberately no UPDATE policy for package objects. Every corrected
-- package is uploaded under a new immutable version path.

commit;
