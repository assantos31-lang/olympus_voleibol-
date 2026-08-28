begin;

-- Quem ministra o treino é definido exclusivamente pelo Admin em convocations.
-- Esta função passa a definir somente quem prepara o planejamento.
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
      and tsa.user_id = auth.uid()
      and tsa.status = 'active'
      and tsa.technical_role = 'technical_coordinator'
      and tsa.can_approve_training
  ) then
    raise exception 'Somente o coordenador pode liberar este planejamento.';
  end if;

  if not exists (
    select 1 from public.technical_staff_assignments tsa
    where tsa.organization_id = organization_id_value
      and tsa.user_id = p_coach_id
      and tsa.status = 'active'
  ) then
    raise exception 'O responsável escolhido não pertence à equipe técnica ativa.';
  end if;

  if p_coach_id <> auth.uid() and not exists (
    select 1 from public.technical_staff_assignments target
    where target.organization_id = organization_id_value
      and target.user_id = p_coach_id
      and target.status = 'active'
      and target.supervisor_user_id = auth.uid()
  ) then
    raise exception 'O profissional não está abaixo deste coordenador.';
  end if;

  insert into public.training_planning_workflows
    (event_id, organization_id, assigned_coach_id, status,
     enabled_by, enabled_at, updated_at)
  values (p_event_id, organization_id_value, p_coach_id, 'enabled',
          auth.uid(), now(), now())
  on conflict (event_id) do update
    set assigned_coach_id = excluded.assigned_coach_id,
        status = 'enabled', enabled_by = auth.uid(),
        enabled_at = now(), published_by = null,
        published_at = null, updated_at = now();
end;
$$;

revoke all on function public.enable_training_planning_v1(uuid, uuid) from public;
grant execute on function public.enable_training_planning_v1(uuid, uuid)
  to authenticated, service_role;

create index if not exists convocations_coach_assignment_lookup_v2
  on public.convocations (user_id, event_role, event_id);

create index if not exists training_planning_workflows_planner_status_v2
  on public.training_planning_workflows (assigned_coach_id, status, event_id);

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
      and tsa.user_id = auth.uid()
      and tsa.status = 'active'
      and tsa.technical_role = 'technical_coordinator'
  )
);

commit;
