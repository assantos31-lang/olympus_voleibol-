-- Olympus / Plataforma de Clubes
-- Fase 2: clube ativo, identidade por organização e associação automática.

begin;

insert into public.organization_settings (
  organization_id,
  key,
  value
)
select id, 'app_branding', branding
from public.organizations
where lower(slug) = 'olympus'
on conflict (organization_id, key) do nothing;

create or replace function public.sync_organization_membership_v1(
  target_user_id uuid,
  target_organization_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  profile_row public.profiles%rowtype;
  resolved_role text;
begin
  select *
  into profile_row
  from public.profiles p
  where p.id = target_user_id
    and p.organization_id = target_organization_id;

  if not found then
    return;
  end if;

  resolved_role := case
    when exists (
      select 1
      from public.user_roles ur
      where ur.user_id = target_user_id
        and ur.organization_id = target_organization_id
        and ur.is_active
        and lower(ur.role) in ('owner', 'master', 'super_admin')
    ) then 'owner'
    when exists (
      select 1
      from public.user_roles ur
      where ur.user_id = target_user_id
        and ur.organization_id = target_organization_id
        and ur.is_active
        and lower(ur.role) = 'admin'
    ) or lower(profile_row.user_type) = 'admin' then 'admin'
    when exists (
      select 1
      from public.user_roles ur
      where ur.user_id = target_user_id
        and ur.organization_id = target_organization_id
        and ur.is_active
        and lower(ur.role) in ('coach', 'treinador')
    ) or lower(profile_row.user_type) in ('coach', 'treinador') then 'coach'
    when exists (
      select 1
      from public.user_roles ur
      where ur.user_id = target_user_id
        and ur.organization_id = target_organization_id
        and ur.is_active
        and lower(ur.role) in ('athlete', 'atleta')
    ) or lower(profile_row.user_type) in ('athlete', 'atleta') then 'athlete'
    else 'member'
  end;

  insert into public.organization_members (
    organization_id,
    user_id,
    role,
    status,
    is_default
  )
  values (
    target_organization_id,
    target_user_id,
    resolved_role,
    case when profile_row.is_active then 'active' else 'suspended' end,
    true
  )
  on conflict (organization_id, user_id) do update
  set role = excluded.role,
      status = excluded.status,
      is_default = excluded.is_default,
      updated_at = now();
end;
$$;

create or replace function public.sync_profile_organization_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    update public.organization_members
    set status = 'removed',
        is_default = false,
        updated_at = now()
    where organization_id = old.organization_id
      and user_id = old.id;
    return old;
  end if;

  if tg_op = 'UPDATE'
     and old.organization_id is distinct from new.organization_id then
    update public.organization_members
    set status = 'removed',
        is_default = false,
        updated_at = now()
    where organization_id = old.organization_id
      and user_id = old.id;
  end if;

  perform public.sync_organization_membership_v1(
    new.id,
    new.organization_id
  );
  return new;
end;
$$;

create or replace function public.sync_user_role_organization_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    perform public.sync_organization_membership_v1(
      old.user_id,
      old.organization_id
    );
    return old;
  end if;

  if tg_op = 'UPDATE'
     and (old.user_id is distinct from new.user_id
       or old.organization_id is distinct from new.organization_id) then
    perform public.sync_organization_membership_v1(
      old.user_id,
      old.organization_id
    );
  end if;

  perform public.sync_organization_membership_v1(
    new.user_id,
    new.organization_id
  );
  return new;
end;
$$;

drop trigger if exists profiles_sync_organization_v1 on public.profiles;
create trigger profiles_sync_organization_v1
after insert or update or delete
on public.profiles
for each row execute function public.sync_profile_organization_v1();

drop trigger if exists user_roles_sync_organization_v1 on public.user_roles;
create trigger user_roles_sync_organization_v1
after insert or update or delete
on public.user_roles
for each row execute function public.sync_user_role_organization_v1();

revoke all on function public.sync_organization_membership_v1(uuid, uuid)
  from public;
revoke all on function public.sync_profile_organization_v1()
  from public;
revoke all on function public.sync_user_role_organization_v1()
  from public;

do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'organization_settings'
  ) then
    alter publication supabase_realtime
      add table public.organization_settings;
  end if;
end;
$$;

commit;
