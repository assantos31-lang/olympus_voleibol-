begin;

create or replace function public.get_coach_assigned_trainings_v1(
  p_coach_id uuid
)
returns table (
  event_id uuid,
  event_name text,
  event_date text,
  event_time text,
  event_end_time text,
  gender text,
  city text,
  state text,
  planner_id uuid,
  planning_status text,
  block_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  organization_id_value uuid := public.current_organization_id();
begin
  if auth.uid() is null or organization_id_value is null then
    return;
  end if;

  if p_coach_id <> auth.uid()
     and not public.is_organization_admin(organization_id_value)
     and not exists (
       select 1
       from public.technical_staff_assignments target
       where target.organization_id = organization_id_value
         and target.user_id = p_coach_id
         and target.supervisor_user_id = auth.uid()
         and target.status = 'active'
     ) then
    raise exception 'O profissional não está sob sua visão técnica.';
  end if;

  return query
  select
    e.id,
    coalesce(e.event_name, 'Treino')::text,
    e.event_date::text,
    e.event_time::text,
    e.event_end_time::text,
    e.gender::text,
    e.city::text,
    e.state::text,
    w.assigned_coach_id,
    coalesce(w.status, 'pending')::text,
    count(distinct b.id)::bigint
  from public.convocations c
  join public.events e on e.id = c.event_id
  left join public.training_planning_workflows w on w.event_id = e.id
  left join public.training_plan_blocks b on b.event_id = e.id
  where c.user_id = p_coach_id
    and lower(trim(coalesce(c.event_role, ''))) = 'coach'
    and e.organization_id = organization_id_value
    and lower(trim(coalesce(e.event_type, ''))) = 'treino'
  group by e.id, e.event_name, e.event_date, e.event_time,
           e.event_end_time, e.gender, e.city, e.state,
           w.assigned_coach_id, w.status
  order by e.event_date, e.event_time;
end;
$$;

revoke all on function public.get_coach_assigned_trainings_v1(uuid) from public;
grant execute on function public.get_coach_assigned_trainings_v1(uuid)
  to authenticated, service_role;

commit;
