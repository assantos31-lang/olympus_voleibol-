-- Permite que administradores com múltiplos perfis gerenciem fotos dos
-- eventos do próprio clube, sem ampliar acesso entre organizações.

begin;

create or replace function public.can_manage_event_photos_v1(
  target_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
    and (
      public.is_platform_admin_v1()
      or public.is_organization_admin(target_organization_id)
      or (
        public.is_current_user_admin_v1()
        and public.is_organization_member(target_organization_id)
        and target_organization_id = public.current_organization_id()
      )
    )
$$;

revoke all on function public.can_manage_event_photos_v1(uuid) from public;
grant execute on function public.can_manage_event_photos_v1(uuid)
  to authenticated, service_role;

alter table public.event_photos enable row level security;

drop policy if exists event_photos_member_select_v1 on public.event_photos;
create policy event_photos_member_select_v1
on public.event_photos
for select
to authenticated
using (public.can_access_tenant_v1(organization_id));

drop policy if exists event_photos_admin_insert_v1 on public.event_photos;
create policy event_photos_admin_insert_v1
on public.event_photos
for insert
to authenticated
with check (public.can_manage_event_photos_v1(organization_id));

drop policy if exists event_photos_admin_update_v1 on public.event_photos;
create policy event_photos_admin_update_v1
on public.event_photos
for update
to authenticated
using (public.can_manage_event_photos_v1(organization_id))
with check (public.can_manage_event_photos_v1(organization_id));

drop policy if exists event_photos_admin_delete_v1 on public.event_photos;
create policy event_photos_admin_delete_v1
on public.event_photos
for delete
to authenticated
using (public.can_manage_event_photos_v1(organization_id));

grant select, insert, update, delete on public.event_photos to authenticated;

commit;
