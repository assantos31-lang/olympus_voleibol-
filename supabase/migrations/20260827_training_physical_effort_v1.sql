begin;

alter table public.training_plan_blocks
  add column if not exists physical_effort_percent smallint not null default 0,
  add column if not exists physical_minutes integer not null default 0;

alter table public.training_plan_blocks
  drop constraint if exists training_plan_blocks_physical_effort_percent_check,
  add constraint training_plan_blocks_physical_effort_percent_check
    check (physical_effort_percent between 0 and 100),
  drop constraint if exists training_plan_blocks_physical_minutes_check,
  add constraint training_plan_blocks_physical_minutes_check
    check (physical_minutes >= 0);

-- Blocos físicos antigos passam a representar 100% de esforço físico.
update public.training_plan_blocks
set physical_effort_percent = 100,
    physical_minutes = greatest(
      0,
      round(extract(epoch from (end_time - start_time)) / 60)::integer
    )
where lower(trim(category)) in ('físico', 'fisico')
  and physical_effort_percent = 0;

create or replace function public.sync_training_block_physical_minutes_v1()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  duration_minutes integer;
begin
  duration_minutes := greatest(
    0,
    round(extract(epoch from (new.end_time - new.start_time)) / 60)::integer
  );
  new.physical_effort_percent := greatest(
    0,
    least(100, coalesce(new.physical_effort_percent, 0))
  );
  new.physical_minutes := round(
    duration_minutes * new.physical_effort_percent / 100.0
  )::integer;
  return new;
end;
$$;

drop trigger if exists training_block_physical_minutes_sync_v1
  on public.training_plan_blocks;
create trigger training_block_physical_minutes_sync_v1
before insert or update of start_time, end_time, physical_effort_percent
on public.training_plan_blocks
for each row execute function public.sync_training_block_physical_minutes_v1();

revoke all on function public.sync_training_block_physical_minutes_v1()
  from public;

create or replace function public.get_checked_in_training_plan_blocks_for_athlete_v2(
  p_athlete_id uuid default null
)
returns table (
  id uuid,
  event_id uuid,
  coach_id uuid,
  category text,
  type text,
  start_time text,
  end_time text,
  duration_minutes integer,
  physical_effort_percent integer,
  physical_minutes integer,
  event_type text,
  gender text,
  event_date text,
  event_time text
)
language sql
stable
security definer
set search_path = ''
as $$
  with requested as (
    select coalesce(p_athlete_id, auth.uid()) as athlete_id
  )
  select
    b.id,
    b.event_id,
    b.coach_id,
    b.category,
    b.type,
    b.start_time::text,
    b.end_time::text,
    greatest(
      0,
      round(extract(epoch from (b.end_time - b.start_time)) / 60)::integer
    ),
    b.physical_effort_percent::integer,
    b.physical_minutes,
    e.event_type,
    e.gender,
    e.event_date::text,
    e.event_time::text
  from requested r
  join public.checkins c
    on c.user_id = r.athlete_id
   and lower(coalesce(c.check_in_status, '')) in ('realizado', 'completed')
  join public.events e on e.id = c.event_id
  join public.training_plan_blocks b on b.event_id = e.id
  where r.athlete_id = auth.uid()
     or public.is_organization_admin(e.organization_id)
  order by e.event_date desc, b.position;
$$;

create or replace function public.get_training_physical_summary_v1()
returns table (
  coach_id uuid,
  month date,
  physical_minutes bigint
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    b.coach_id,
    date_trunc('month', to_date(e.event_date::text, 'DD/MM/YYYY'))::date,
    sum(
      case
        when lower(trim(b.category)) in ('físico', 'fisico') then 0
        else b.physical_minutes
      end
    )::bigint
  from public.training_plan_blocks b
  join public.events e on e.id = b.event_id
  where b.coach_id = auth.uid()
  group by b.coach_id,
    date_trunc('month', to_date(e.event_date::text, 'DD/MM/YYYY'))::date;
$$;

revoke all on function public.get_checked_in_training_plan_blocks_for_athlete_v2(uuid)
  from public, anon;
revoke all on function public.get_training_physical_summary_v1()
  from public, anon;
grant execute on function public.get_checked_in_training_plan_blocks_for_athlete_v2(uuid)
  to authenticated, service_role;
grant execute on function public.get_training_physical_summary_v1()
  to authenticated, service_role;

commit;
