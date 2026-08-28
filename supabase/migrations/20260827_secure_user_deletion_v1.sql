begin;

-- Usada exclusivamente pela Edge Function com service_role para localizar
-- arquivos que precisam ser removidos pela Storage API antes da conta.
create or replace function public.list_user_owned_storage_objects_v1(
  p_user_id uuid
)
returns table (
  bucket_id text,
  object_name text
)
language sql
security definer
set search_path = ''
as $$
  select so.bucket_id, so.name
  from storage.objects so
  where so.owner_id = p_user_id::text
  order by so.bucket_id, so.name
$$;

revoke all on function public.list_user_owned_storage_objects_v1(uuid)
  from public, anon, authenticated;
grant execute on function public.list_user_owned_storage_objects_v1(uuid)
  to service_role;

commit;
