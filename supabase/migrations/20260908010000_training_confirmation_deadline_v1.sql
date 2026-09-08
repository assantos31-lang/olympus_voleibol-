begin;

insert into public.organization_settings (organization_id, key, value)
select
  o.id,
  'training_confirmation_deadline',
  jsonb_build_object('enabled', false, 'hours_before', 3)
from public.organizations o
on conflict (organization_id, key) do nothing;

create or replace function public.training_event_start_at_v1(
  p_event_date text,
  p_event_time text
)
returns timestamptz
language plpgsql
stable
set search_path = ''
as $$
declare
  date_value date;
  time_value time;
begin
  if coalesce(trim(p_event_date), '') = '' or
     coalesce(trim(p_event_time), '') = '' then
    return null;
  end if;

  if trim(p_event_date) ~ '^\d{2}/\d{2}/\d{4}$' then
    date_value := to_date(trim(p_event_date), 'DD/MM/YYYY');
  elsif trim(p_event_date) ~ '^\d{4}-\d{2}-\d{2}$' then
    date_value := trim(p_event_date)::date;
  else
    return null;
  end if;
  time_value := trim(p_event_time)::time;
  return (date_value + time_value) at time zone 'America/Sao_Paulo';
exception when others then
  return null;
end;
$$;

create table if not exists public.training_confirmation_deadline_notifications (
  convocation_id uuid primary key references public.convocations(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  event_name text not null default 'Treino',
  deadline_at timestamptz not null,
  claimed_at timestamptz,
  sent_at timestamptz,
  attempts integer not null default 0,
  last_error text,
  created_at timestamptz not null default now()
);

create index if not exists training_confirmation_deadline_notifications_due_idx
  on public.training_confirmation_deadline_notifications (sent_at, claimed_at);

alter table public.training_confirmation_deadline_notifications enable row level security;
revoke all on public.training_confirmation_deadline_notifications from anon, authenticated;

create or replace function public.enforce_training_confirmation_deadline_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  event_organization_id uuid;
  event_type text;
  event_date_text text;
  event_time_text text;
  setting_value jsonb;
  enabled boolean := false;
  hours_before integer := 3;
  deadline_at timestamptz;
begin
  if lower(coalesce(new.status, '')) <> 'accepted' or
     (tg_op = 'UPDATE' and lower(coalesce(old.status, '')) = 'accepted') or
     lower(coalesce(new.event_role, 'athlete')) not in ('athlete', 'atleta') then
    return new;
  end if;

  select e.organization_id, e.event_type, e.event_date::text, e.event_time::text
    into event_organization_id, event_type, event_date_text, event_time_text
  from public.events e
  where e.id = new.event_id;

  if not found or lower(trim(coalesce(event_type, ''))) <> 'treino' then
    return new;
  end if;

  if auth.uid() is null or public.is_organization_admin(event_organization_id) then
    return new;
  end if;

  select s.value
    into setting_value
  from public.organization_settings s
  where s.organization_id = event_organization_id
    and s.key = 'training_confirmation_deadline';

  enabled := coalesce((setting_value ->> 'enabled')::boolean, false);
  if not enabled then return new; end if;

  hours_before := greatest(
    1,
    least(168, coalesce((setting_value ->> 'hours_before')::integer, 3))
  );
  deadline_at := public.training_event_start_at_v1(
    event_date_text,
    event_time_text
  ) - make_interval(hours => hours_before);

  if deadline_at is not null and clock_timestamp() >= deadline_at then
    raise exception using
      errcode = 'P0001',
      message = 'O prazo para confirmar sua presença neste treino expirou. Você não deverá comparecer ao treino.';
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_training_confirmation_deadline_v1
  on public.convocations;
drop trigger if exists enforce_training_confirmation_deadline_insert_v1
  on public.convocations;
create trigger enforce_training_confirmation_deadline_v1
before update of status on public.convocations
for each row execute function public.enforce_training_confirmation_deadline_v1();
create trigger enforce_training_confirmation_deadline_insert_v1
before insert on public.convocations
for each row execute function public.enforce_training_confirmation_deadline_v1();

create or replace function public.claim_expired_training_confirmations_v1(
  p_limit integer default 100
)
returns table (
  convocation_id uuid,
  organization_id uuid,
  event_id uuid,
  user_id uuid,
  event_name text,
  deadline_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  return query
  with candidates as (
    select
      c.id as convocation_id,
      e.organization_id,
      e.id as event_id,
      c.user_id,
      coalesce(nullif(trim(e.event_name), ''), 'Treino') as event_name,
      public.training_event_start_at_v1(
        e.event_date::text,
        e.event_time::text
      ) - make_interval(
        hours => greatest(
          1,
          least(168, coalesce((s.value ->> 'hours_before')::integer, 3))
        )
      ) as confirmation_deadline_at
    from public.convocations c
    join public.events e on e.id = c.event_id
    join public.organization_settings s
      on s.organization_id = e.organization_id
     and s.key = 'training_confirmation_deadline'
    left join public.training_confirmation_deadline_notifications n
      on n.convocation_id = c.id
    where lower(coalesce(e.event_type, '')) = 'treino'
      and lower(coalesce(c.event_role, 'athlete')) in ('athlete', 'atleta')
      and lower(coalesce(c.status, 'pending')) = 'pending'
      and coalesce((s.value ->> 'enabled')::boolean, false)
      and public.training_event_start_at_v1(
            e.event_date::text,
            e.event_time::text
          ) > clock_timestamp()
      and public.training_event_start_at_v1(
            e.event_date::text,
            e.event_time::text
          ) - make_interval(
            hours => greatest(
              1,
              least(168, coalesce((s.value ->> 'hours_before')::integer, 3))
            )
          ) <= clock_timestamp()
      and n.sent_at is null
      and (n.claimed_at is null or n.claimed_at < clock_timestamp() - interval '10 minutes')
    order by confirmation_deadline_at
    limit greatest(1, least(coalesce(p_limit, 100), 500))
    for update of c skip locked
  ), claimed as (
    insert into public.training_confirmation_deadline_notifications (
      convocation_id,
      organization_id,
      event_id,
      user_id,
      event_name,
      deadline_at,
      claimed_at,
      attempts,
      last_error
    )
    select
      candidate.convocation_id,
      candidate.organization_id,
      candidate.event_id,
      candidate.user_id,
      candidate.event_name,
      candidate.confirmation_deadline_at,
      clock_timestamp(),
      1,
      null
    from candidates candidate
    on conflict on constraint training_confirmation_deadline_notifications_pkey
      do update
      set claimed_at = clock_timestamp(),
          attempts = public.training_confirmation_deadline_notifications.attempts + 1,
          last_error = null
      where public.training_confirmation_deadline_notifications.sent_at is null
        and (
          public.training_confirmation_deadline_notifications.claimed_at is null or
          public.training_confirmation_deadline_notifications.claimed_at <
            clock_timestamp() - interval '10 minutes'
        )
    returning public.training_confirmation_deadline_notifications.convocation_id
  )
  select
    candidate.convocation_id,
    candidate.organization_id,
    candidate.event_id,
    candidate.user_id,
    candidate.event_name,
    candidate.confirmation_deadline_at
  from candidates candidate
  join claimed
    on claimed.convocation_id = candidate.convocation_id;
end;
$$;

revoke all on function public.training_event_start_at_v1(text, text) from public;
grant execute on function public.training_event_start_at_v1(text, text) to authenticated, service_role;
revoke all on function public.claim_expired_training_confirmations_v1(integer) from public;
grant execute on function public.claim_expired_training_confirmations_v1(integer) to service_role;

do $$
begin
  if exists (
    select 1
    from pg_publication
    where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'organization_settings'
  ) then
    alter publication supabase_realtime add table public.organization_settings;
  end if;
end;
$$;

commit;
