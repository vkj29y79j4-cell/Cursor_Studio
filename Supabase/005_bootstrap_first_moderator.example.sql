-- Run once in the Supabase SQL Editor after the first moderator has created
-- and confirmed their Cursor Studio account. Replace the placeholder handle.
--
-- This cannot be done with a publishable client key by design.

insert into app_private.moderators (user_id)
select id
from public.profiles
where handle = 'REPLACE_WITH_CREATOR_HANDLE'
on conflict (user_id) do nothing;
