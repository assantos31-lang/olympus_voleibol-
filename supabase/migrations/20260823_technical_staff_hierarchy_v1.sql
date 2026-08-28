-- Olympus / Equipe tecnica por organizacao.
-- O administrador nomeia os profissionais e define a cadeia de supervisao.

begin;

create table if not exists public.technical_staff_assignments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  technical_role text not null
    check (technical_role in (
      'technical_coordinator',
      'head_coach',
      'assistant_coach',
      'intern'
    )),
  supervisor_user_id uuid references auth.users(id) on delete set null,
  team_scope text not null default 'all',
  can_create_training boolean not null default true,
  can_publish_training boolean not null default false,
  can_approve_training boolean not null default false,
  can_manage_staff boolean not null default false,
  status text not null default 'active'
    check (status in ('active', 'suspended', 'removed')),
  assigned_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, user_id),
  check (supervisor_user_id is null or supervisor_user_id <> user_id)
);

create index if not exists technical_staff_org_status_idx
  on public.technical_staff_assignments (organization_id, status, technical_role);
create index if not exists technical_staff_supervisor_idx
  on public.technical_staff_assignments (
    organization_id,
    supervisor_user_id,
    status
  );

create or replace function public.is_technical_coordinator_v1(
  target_organization uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.technical_staff_assignments tsa
    where tsa.organization_id = target_organization
      and tsa.user_id = auth.uid()
      and tsa.status = 'active'
      and tsa.technical_role = 'technical_coordinator'
      and tsa.can_manage_staff
  )
$$;

create or replace function public.validate_technical_supervisor_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  supervisor_role text;
begin
  new.updated_at := now();

  if new.technical_role = 'technical_coordinator' then
    new.supervisor_user_id := null;
    return new;
  end if;

  if new.supervisor_user_id is null then
    return new;
  end if;

  select tsa.technical_role
    into supervisor_role
  from public.technical_staff_assignments tsa
  where tsa.organization_id = new.organization_id
    and tsa.user_id = new.supervisor_user_id
    and tsa.status = 'active';

  if supervisor_role is null then
    raise exception 'O superior escolhido nao pertence a equipe tecnica ativa.';
  end if;

  if new.technical_role = 'head_coach'
     and supervisor_role <> 'technical_coordinator' then
    raise exception 'O treinador responsavel deve responder a um coordenador tecnico.';
  end if;

  if new.technical_role in ('assistant_coach', 'intern')
     and supervisor_role not in ('technical_coordinator', 'head_coach') then
    raise exception 'Assistentes e estagiarios devem responder a um coordenador ou treinador responsavel.';
  end if;

  return new;
end;
$$;

drop trigger if exists technical_staff_validate_supervisor_v1
  on public.technical_staff_assignments;
create trigger technical_staff_validate_supervisor_v1
before insert or update on public.technical_staff_assignments
for each row execute function public.validate_technical_supervisor_v1();

create or replace function public.admin_set_technical_staff_v1(
  p_user_id uuid,
  p_technical_role text,
  p_supervisor_user_id uuid default null,
  p_team_scope text default 'all',
  p_can_create_training boolean default true,
  p_can_publish_training boolean default false,
  p_can_approve_training boolean default false,
  p_can_manage_staff boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  organization_id_value uuid;
  assignment_id uuid;
begin
  organization_id_value := public.current_organization_id();

  if organization_id_value is null
     or not public.is_organization_admin(organization_id_value) then
    raise exception 'Apenas o administrador pode liberar a equipe tecnica.';
  end if;

  if not exists (
    select 1
    from public.organization_members om
    where om.organization_id = organization_id_value
      and om.user_id = p_user_id
      and om.status = 'active'
  ) then
    raise exception 'O profissional precisa ser um usuario ativo do clube.';
  end if;

  insert into public.user_roles (
    user_id,
    role,
    is_active,
    organization_id,
    updated_at
  )
  values (
    p_user_id,
    'coach',
    true,
    organization_id_value,
    now()
  )
  on conflict (user_id, role) do update
  set is_active = true,
      organization_id = excluded.organization_id,
      updated_at = now();

  insert into public.technical_staff_assignments (
    organization_id,
    user_id,
    technical_role,
    supervisor_user_id,
    team_scope,
    can_create_training,
    can_publish_training,
    can_approve_training,
    can_manage_staff,
    status,
    assigned_by,
    updated_at
  )
  values (
    organization_id_value,
    p_user_id,
    p_technical_role,
    p_supervisor_user_id,
    coalesce(nullif(trim(p_team_scope), ''), 'all'),
    p_can_create_training,
    p_can_publish_training,
    p_can_approve_training,
    p_can_manage_staff,
    'active',
    auth.uid(),
    now()
  )
  on conflict (organization_id, user_id) do update
  set technical_role = excluded.technical_role,
      supervisor_user_id = excluded.supervisor_user_id,
      team_scope = excluded.team_scope,
      can_create_training = excluded.can_create_training,
      can_publish_training = excluded.can_publish_training,
      can_approve_training = excluded.can_approve_training,
      can_manage_staff = excluded.can_manage_staff,
      status = 'active',
      assigned_by = auth.uid(),
      updated_at = now()
  returning id into assignment_id;

  return assignment_id;
end;
$$;

alter table public.technical_staff_assignments enable row level security;

drop policy if exists technical_staff_select_v1
  on public.technical_staff_assignments;
create policy technical_staff_select_v1
on public.technical_staff_assignments for select to authenticated
using (
  public.is_organization_admin(organization_id)
  or user_id = auth.uid()
  or supervisor_user_id = auth.uid()
  or public.is_technical_coordinator_v1(organization_id)
);

drop policy if exists technical_staff_admin_insert_v1
  on public.technical_staff_assignments;
create policy technical_staff_admin_insert_v1
on public.technical_staff_assignments for insert to authenticated
with check (
  public.is_organization_admin(organization_id)
  and assigned_by = auth.uid()
);

drop policy if exists technical_staff_admin_update_v1
  on public.technical_staff_assignments;
create policy technical_staff_admin_update_v1
on public.technical_staff_assignments for update to authenticated
using (public.is_organization_admin(organization_id))
with check (public.is_organization_admin(organization_id));

drop policy if exists technical_staff_admin_delete_v1
  on public.technical_staff_assignments;
create policy technical_staff_admin_delete_v1
on public.technical_staff_assignments for delete to authenticated
using (public.is_organization_admin(organization_id));

revoke all on function public.is_technical_coordinator_v1(uuid) from public;
revoke all on function public.validate_technical_supervisor_v1() from public;
revoke all on function public.admin_set_technical_staff_v1(
  uuid, text, uuid, text, boolean, boolean, boolean, boolean
) from public;
grant execute on function public.is_technical_coordinator_v1(uuid)
  to authenticated, service_role;
grant execute on function public.admin_set_technical_staff_v1(
  uuid, text, uuid, text, boolean, boolean, boolean, boolean
) to authenticated, service_role;
grant select, insert, update, delete on public.technical_staff_assignments
  to authenticated;

commit;
