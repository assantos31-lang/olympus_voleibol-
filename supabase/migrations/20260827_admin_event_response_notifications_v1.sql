begin;

create table if not exists public.admin_notification_preferences (
  admin_id uuid primary key references auth.users(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  notify_event_responses boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists admin_notification_preferences_org_idx
  on public.admin_notification_preferences (organization_id, notify_event_responses);

create table if not exists public.admin_notifications (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  admin_id uuid not null references auth.users(id) on delete cascade,
  notification_type text not null default 'general',
  title text not null,
  body text not null,
  athlete_name text,
  event_id uuid references public.events(id) on delete set null,
  source_key text,
  is_read boolean not null default false,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.admin_notifications
  add column if not exists organization_id uuid references public.organizations(id) on delete cascade,
  add column if not exists admin_id uuid references auth.users(id) on delete cascade,
  add column if not exists notification_type text not null default 'general',
  add column if not exists title text,
  add column if not exists body text,
  add column if not exists athlete_name text,
  add column if not exists event_id uuid references public.events(id) on delete set null,
  add column if not exists source_key text,
  add column if not exists is_read boolean not null default false,
  add column if not exists read_at timestamptz,
  add column if not exists created_at timestamptz not null default now();

create unique index if not exists admin_notifications_source_unique_idx
  on public.admin_notifications (admin_id, source_key)
  where source_key is not null;
create index if not exists admin_notifications_admin_created_idx
  on public.admin_notifications (admin_id, created_at desc);

alter table public.admin_notification_preferences enable row level security;
alter table public.admin_notifications enable row level security;

drop policy if exists admin_notification_preferences_select_self_v1
  on public.admin_notification_preferences;
create policy admin_notification_preferences_select_self_v1
on public.admin_notification_preferences for select to authenticated
using (admin_id = auth.uid() and public.is_organization_admin(organization_id));

drop policy if exists admin_notification_preferences_insert_self_v1
  on public.admin_notification_preferences;
create policy admin_notification_preferences_insert_self_v1
on public.admin_notification_preferences for insert to authenticated
with check (admin_id = auth.uid() and public.is_organization_admin(organization_id));

drop policy if exists admin_notification_preferences_update_self_v1
  on public.admin_notification_preferences;
create policy admin_notification_preferences_update_self_v1
on public.admin_notification_preferences for update to authenticated
using (admin_id = auth.uid() and public.is_organization_admin(organization_id))
with check (admin_id = auth.uid() and public.is_organization_admin(organization_id));

drop policy if exists admin_notifications_select_self_v1
  on public.admin_notifications;
create policy admin_notifications_select_self_v1
on public.admin_notifications for select to authenticated
using (admin_id = auth.uid());

drop policy if exists admin_notifications_update_self_v1
  on public.admin_notifications;
create policy admin_notifications_update_self_v1
on public.admin_notifications for update to authenticated
using (admin_id = auth.uid())
with check (admin_id = auth.uid());

drop policy if exists admin_notifications_delete_self_v1
  on public.admin_notifications;
create policy admin_notifications_delete_self_v1
on public.admin_notifications for delete to authenticated
using (admin_id = auth.uid());

revoke all on public.admin_notification_preferences from anon;
revoke all on public.admin_notifications from anon;
grant select, insert, update on public.admin_notification_preferences to authenticated;
grant select, update, delete on public.admin_notifications to authenticated;

create or replace function public.notify_admins_event_response_v1(
  p_event_id uuid,
  p_status text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_organization_id uuid;
  v_event_name text;
  v_athlete_name text;
  v_status text := lower(trim(coalesce(p_status, '')));
  v_count integer := 0;
begin
  if v_user_id is null then
    raise exception 'Usuário não autenticado';
  end if;
  if v_status not in ('accepted', 'rejected') then
    raise exception 'Status inválido';
  end if;

  select e.organization_id, coalesce(e.event_name, 'evento')
    into v_organization_id, v_event_name
  from public.events e
  join public.convocations c
    on c.event_id = e.id
   and c.user_id = v_user_id
  where e.id = p_event_id
    and lower(coalesce(c.event_role, 'athlete')) <> 'coach'
    and lower(coalesce(c.status, 'pending')) = v_status
  limit 1;

  if v_organization_id is null then
    raise exception 'Convocação não encontrada ou resposta ainda não registrada';
  end if;

  select coalesce(nullif(trim(p.full_name), ''), 'Atleta')
    into v_athlete_name
  from public.profiles p
  where p.id = v_user_id
    and p.organization_id = v_organization_id
  limit 1;

  insert into public.admin_notifications (
    organization_id,
    admin_id,
    notification_type,
    title,
    body,
    athlete_name,
    event_id,
    source_key
  )
  select
    pref.organization_id,
    pref.admin_id,
    'event_response',
    case when v_status = 'accepted'
      then 'Convocação aceita'
      else 'Convocação recusada'
    end,
    format(
      '%s %s o evento %s.',
      coalesce(v_athlete_name, 'Atleta'),
      case when v_status = 'accepted' then 'aceitou' else 'recusou' end,
      v_event_name
    ),
    coalesce(v_athlete_name, 'Atleta'),
    p_event_id,
    format('event_response:%s:%s:%s', p_event_id, v_user_id, v_status)
  from public.admin_notification_preferences pref
  join public.organization_members member
    on member.organization_id = pref.organization_id
   and member.user_id = pref.admin_id
   and member.status = 'active'
   and member.role in ('owner', 'admin')
  where pref.organization_id = v_organization_id
    and pref.notify_event_responses = true
  on conflict (admin_id, source_key) where source_key is not null do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.notify_admins_event_response_v1(uuid, text) from public;
grant execute on function public.notify_admins_event_response_v1(uuid, text)
  to authenticated, service_role;

do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'admin_notifications'
  ) then
    alter publication supabase_realtime add table public.admin_notifications;
  end if;
end;
$$;

commit;
