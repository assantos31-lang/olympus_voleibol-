begin;

create table if not exists public.training_planning_workflows (
  event_id uuid primary key references public.events(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  assigned_coach_id uuid references auth.users(id) on delete set null,
  status text not null default 'pending'
    check (status in ('pending', 'enabled', 'published')),
  enabled_by uuid references auth.users(id) on delete set null,
  enabled_at timestamptz,
  published_by uuid references auth.users(id) on delete set null,
  published_at timestamptz,
  last_coordinator_reminder_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists training_planning_workflows_pending_idx
  on public.training_planning_workflows
  (organization_id, status, last_coordinator_reminder_at);

create or replace function public.ensure_training_planning_workflow_v1()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if lower(trim(new.event_type)) = 'treino' and new.organization_id is not null then
    insert into public.training_planning_workflows
      (event_id, organization_id, status, updated_at)
    values (new.id, new.organization_id, 'pending', now())
    on conflict (event_id) do update
      set organization_id = excluded.organization_id, updated_at = now();
  end if;
  return new;
end;
$$;

drop trigger if exists events_training_planning_workflow_v1 on public.events;
create trigger events_training_planning_workflow_v1
after insert or update of event_type, organization_id on public.events
for each row execute function public.ensure_training_planning_workflow_v1();

insert into public.training_planning_workflows
  (event_id, organization_id, status, published_at)
select e.id, e.organization_id,
  case when exists (
    select 1 from public.training_plan_blocks b where b.event_id = e.id
  ) then 'published' else 'pending' end,
  case when exists (
    select 1 from public.training_plan_blocks b where b.event_id = e.id
  ) then now() else null end
from public.events e
where lower(trim(e.event_type)) = 'treino'
  and e.organization_id is not null
on conflict (event_id) do nothing;

create or replace function public.enable_training_planning_v1(
  p_event_id uuid, p_coach_id uuid
)
returns void language plpgsql security definer set search_path = '' as $$
declare organization_id_value uuid;
begin
  select e.organization_id into organization_id_value
  from public.events e where e.id = p_event_id;
  if organization_id_value is null or not exists (
    select 1 from public.technical_staff_assignments tsa
    where tsa.organization_id = organization_id_value
      and tsa.user_id = auth.uid() and tsa.status = 'active'
      and tsa.technical_role = 'technical_coordinator'
      and tsa.can_approve_training
  ) then
    raise exception 'Somente o coordenador pode liberar este planejamento.';
  end if;
  if not exists (
    select 1 from public.technical_staff_assignments tsa
    where tsa.organization_id = organization_id_value
      and tsa.user_id = p_coach_id and tsa.status = 'active'
  ) then
    raise exception 'O técnico escolhido não pertence à equipe técnica ativa.';
  end if;
  insert into public.training_planning_workflows
    (event_id, organization_id, assigned_coach_id, status,
     enabled_by, enabled_at, updated_at)
  values (p_event_id, organization_id_value, p_coach_id, 'enabled',
          auth.uid(), now(), now())
  on conflict (event_id) do update
    set assigned_coach_id = excluded.assigned_coach_id,
        status = 'enabled', enabled_by = auth.uid(),
        enabled_at = now(), updated_at = now();
  insert into public.convocations (event_id, user_id, event_role, status)
  values (p_event_id, p_coach_id, 'coach', 'accepted')
  on conflict (event_id, user_id) do update
    set event_role = 'coach', status = 'accepted', justification = null;
end;
$$;

create or replace function public.publish_training_planning_v1(p_event_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare organization_id_value uuid;
begin
  select e.organization_id into organization_id_value
  from public.events e where e.id = p_event_id;
  if organization_id_value is null or not exists (
    select 1 from public.technical_staff_assignments tsa
    where tsa.organization_id = organization_id_value
      and tsa.user_id = auth.uid() and tsa.status = 'active'
      and tsa.technical_role = 'technical_coordinator'
      and tsa.can_publish_training and tsa.can_approve_training
  ) then
    raise exception 'Você não possui permissão para publicar este treino.';
  end if;
  if not exists (
    select 1 from public.training_plan_blocks b where b.event_id = p_event_id
  ) then
    raise exception 'Crie ao menos um bloco antes de publicar.';
  end if;
  insert into public.training_planning_workflows
    (event_id, organization_id, status, published_by, published_at, updated_at)
  values (p_event_id, organization_id_value, 'published', auth.uid(), now(), now())
  on conflict (event_id) do update
    set status = 'published', published_by = auth.uid(),
        published_at = now(), updated_at = now();
end;
$$;

alter table public.training_planning_workflows enable row level security;
drop policy if exists training_planning_workflows_select_v1
  on public.training_planning_workflows;
create policy training_planning_workflows_select_v1
on public.training_planning_workflows for select to authenticated
using (
  assigned_coach_id = auth.uid()
  or public.is_organization_admin(organization_id)
  or exists (
    select 1 from public.technical_staff_assignments tsa
    where tsa.organization_id = training_planning_workflows.organization_id
      and tsa.user_id = auth.uid() and tsa.status = 'active'
  )
);

revoke all on function public.ensure_training_planning_workflow_v1() from public;
revoke all on function public.enable_training_planning_v1(uuid, uuid) from public;
revoke all on function public.publish_training_planning_v1(uuid) from public;
grant execute on function public.enable_training_planning_v1(uuid, uuid)
  to authenticated, service_role;
grant execute on function public.publish_training_planning_v1(uuid)
  to authenticated, service_role;
grant select on public.training_planning_workflows to authenticated;

create or replace function public.coordinator_set_coach_training_authorization_v1(
  p_coach_id uuid,
  p_authorized boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  organization_id_value uuid;
begin
  select tsa.organization_id into organization_id_value
  from public.technical_staff_assignments tsa
  where tsa.user_id = auth.uid()
    and tsa.status = 'active'
    and tsa.technical_role = 'technical_coordinator'
    and tsa.can_manage_staff
  limit 1;

  if organization_id_value is null then
    raise exception 'Somente o coordenador pode alterar esta autorização.';
  end if;

  if not exists (
    select 1 from public.technical_staff_assignments target
    where target.organization_id = organization_id_value
      and target.user_id = p_coach_id
      and target.status = 'active'
      and target.technical_role <> 'technical_coordinator'
  ) then
    raise exception 'O profissional não está abaixo deste coordenador.';
  end if;

  update public.technical_staff_assignments
  set can_create_training = p_authorized,
      updated_at = now()
  where organization_id = organization_id_value
    and user_id = p_coach_id;

  if not p_authorized then
    update public.training_planning_workflows
    set assigned_coach_id = auth.uid(),
        enabled_by = auth.uid(),
        enabled_at = coalesce(enabled_at, now()),
        status = 'enabled',
        updated_at = now()
    where organization_id = organization_id_value
      and assigned_coach_id = p_coach_id
      and status in ('pending', 'enabled');
  end if;
end;
$$;

revoke all on function public.coordinator_set_coach_training_authorization_v1(uuid, boolean)
  from public;
grant execute on function public.coordinator_set_coach_training_authorization_v1(uuid, boolean)
  to authenticated, service_role;

commit;
