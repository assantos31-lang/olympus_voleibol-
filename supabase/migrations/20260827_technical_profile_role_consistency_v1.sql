begin;

-- Toda pessoa já presente na hierarquia técnica também deve possuir o papel
-- Técnico. Isso corrige registros antigos e mantém o seletor consistente.
insert into public.user_roles (
  user_id,
  role,
  is_active,
  organization_id,
  updated_at
)
select
  tsa.user_id,
  'coach',
  true,
  tsa.organization_id,
  now()
from public.technical_staff_assignments tsa
where tsa.status = 'active'
on conflict (user_id, role) do update
set is_active = true,
    organization_id = excluded.organization_id,
    updated_at = now();

create or replace function public.suspend_orphan_technical_access_v1(
  target_user_id uuid,
  target_organization_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.profiles p
    where p.id = target_user_id
      and p.organization_id = target_organization_id
      and p.is_active
      and lower(coalesce(p.user_type, '')) in (
        'coach', 'treinador', 'tecnico', 'técnico'
      )
  ) and not exists (
    select 1
    from public.user_roles ur
    where ur.user_id = target_user_id
      and ur.organization_id = target_organization_id
      and ur.is_active
      and lower(ur.role) = 'coach'
  ) then
    update public.technical_staff_assignments tsa
    set status = 'suspended',
        updated_at = now()
    where tsa.user_id = target_user_id
      and tsa.organization_id = target_organization_id
      and tsa.status = 'active';
  end if;
end;
$$;

create or replace function public.sync_technical_access_from_user_role_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_user_id uuid;
  target_organization_id uuid;
begin
  target_user_id := case when tg_op = 'DELETE' then old.user_id else new.user_id end;
  target_organization_id := case
    when tg_op = 'DELETE' then old.organization_id
    else new.organization_id
  end;

  perform public.suspend_orphan_technical_access_v1(
    target_user_id,
    target_organization_id
  );
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create or replace function public.sync_technical_access_from_profile_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.suspend_orphan_technical_access_v1(
    new.id,
    new.organization_id
  );
  return new;
end;
$$;

drop trigger if exists user_roles_sync_technical_access_v1
  on public.user_roles;
create trigger user_roles_sync_technical_access_v1
after insert or update or delete on public.user_roles
for each row execute function public.sync_technical_access_from_user_role_v1();

drop trigger if exists profiles_sync_technical_access_v1
  on public.profiles;
create trigger profiles_sync_technical_access_v1
after update of user_type, is_active on public.profiles
for each row execute function public.sync_technical_access_from_profile_v1();

create or replace function public.sync_profile_scope_from_technical_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  resolved_gender text;
begin
  resolved_gender := case new.team_scope
    when 'male' then 'Masculino'
    when 'female' then 'Feminino'
    else 'all'
  end;

  update public.profiles p
  set coach_team_gender = resolved_gender,
      updated_at = now()
  where p.id = new.user_id
    and p.organization_id = new.organization_id
    and coalesce(p.coach_team_gender, 'all') is distinct from resolved_gender;
  return new;
end;
$$;

create or replace function public.sync_technical_scope_from_profile_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  resolved_scope text;
begin
  resolved_scope := case lower(coalesce(new.coach_team_gender, 'all'))
    when 'masculino' then 'male'
    when 'male' then 'male'
    when 'feminino' then 'female'
    when 'female' then 'female'
    else 'all'
  end;

  update public.technical_staff_assignments tsa
  set team_scope = resolved_scope,
      updated_at = now()
  where tsa.user_id = new.id
    and tsa.organization_id = new.organization_id
    and tsa.status = 'active'
    and tsa.team_scope is distinct from resolved_scope;
  return new;
end;
$$;

drop trigger if exists technical_staff_sync_profile_scope_v1
  on public.technical_staff_assignments;
create trigger technical_staff_sync_profile_scope_v1
after insert or update of team_scope on public.technical_staff_assignments
for each row execute function public.sync_profile_scope_from_technical_v1();

drop trigger if exists profiles_sync_technical_scope_v1
  on public.profiles;
create trigger profiles_sync_technical_scope_v1
after update of coach_team_gender on public.profiles
for each row execute function public.sync_technical_scope_from_profile_v1();

update public.profiles p
set coach_team_gender = case tsa.team_scope
      when 'male' then 'Masculino'
      when 'female' then 'Feminino'
      else 'all'
    end,
    updated_at = now()
from public.technical_staff_assignments tsa
where tsa.user_id = p.id
  and tsa.organization_id = p.organization_id
  and tsa.status = 'active'
  and coalesce(p.coach_team_gender, 'all') is distinct from case tsa.team_scope
      when 'male' then 'Masculino'
      when 'female' then 'Feminino'
      else 'all'
    end;

revoke all on function public.suspend_orphan_technical_access_v1(uuid, uuid)
  from public;
revoke all on function public.sync_technical_access_from_user_role_v1()
  from public;
revoke all on function public.sync_technical_access_from_profile_v1()
  from public;
revoke all on function public.sync_profile_scope_from_technical_v1()
  from public;
revoke all on function public.sync_technical_scope_from_profile_v1()
  from public;

commit;
