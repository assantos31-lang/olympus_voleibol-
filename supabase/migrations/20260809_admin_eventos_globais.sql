-- Olympus Voleibol: administracao global de eventos por todos os Admins.

begin;

create or replace function public.is_current_user_admin_v1()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    auth.uid() is not null
    and (
      exists (
        select 1
        from public.profiles p
        where p.id = auth.uid()
          and lower(coalesce(p.user_type::text, '')) = 'admin'
      )
      or exists (
        select 1
        from public.user_roles ur
        where ur.user_id = auth.uid()
          and lower(coalesce(ur.role::text, '')) = 'admin'
          and coalesce(ur.is_active, true)
      )
    );
$$;

revoke all on function public.is_current_user_admin_v1() from public;
grant execute on function public.is_current_user_admin_v1() to authenticated;

-- Mantem as policies atuais dos usuarios comuns e acrescenta acesso Admin.
drop policy if exists events_admin_global_v1 on public.events;
create policy events_admin_global_v1
on public.events for all to authenticated
using (public.is_current_user_admin_v1())
with check (public.is_current_user_admin_v1());

drop policy if exists convocations_admin_global_v1 on public.convocations;
create policy convocations_admin_global_v1
on public.convocations for all to authenticated
using (public.is_current_user_admin_v1())
with check (public.is_current_user_admin_v1());

drop policy if exists checkins_admin_global_v1 on public.checkins;
create policy checkins_admin_global_v1
on public.checkins for all to authenticated
using (public.is_current_user_admin_v1())
with check (public.is_current_user_admin_v1());

drop policy if exists event_rides_admin_global_v1 on public.event_rides;
create policy event_rides_admin_global_v1
on public.event_rides for all to authenticated
using (public.is_current_user_admin_v1())
with check (public.is_current_user_admin_v1());

commit;
