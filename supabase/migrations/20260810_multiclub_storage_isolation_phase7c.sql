-- Olympus / Plataforma de Clubes
-- Fase 7C: separacao dos arquivos por organizacao.

begin;

create or replace function public.storage_object_organization_v1(
  object_name text
)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  segment text;
begin
  if split_part(object_name, '/', 1) <> 'organizations' then
    return public.default_organization_id();
  end if;

  segment := split_part(object_name, '/', 2);
  if segment ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    return segment::uuid;
  end if;

  return null;
end;
$$;

create or replace function public.can_access_storage_object_v1(
  target_bucket text,
  object_name text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when target_bucket not in ('avatars', 'event-images', 'receipts') then true
    when auth.role() = 'service_role' then true
    else public.can_access_tenant_v1(
      public.storage_object_organization_v1(object_name)
    )
  end
$$;

drop policy if exists tenant_storage_restrictive_v1 on storage.objects;
create policy tenant_storage_restrictive_v1
on storage.objects
as restrictive
for all
to public
using (public.can_access_storage_object_v1(bucket_id, name))
with check (public.can_access_storage_object_v1(bucket_id, name));

revoke all on function public.storage_object_organization_v1(text) from public;
revoke all on function public.can_access_storage_object_v1(text, text) from public;
grant execute on function public.can_access_storage_object_v1(text, text)
  to anon, authenticated, service_role;

commit;
