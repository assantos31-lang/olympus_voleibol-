begin;

insert into public.organization_settings (organization_id, key, value)
select o.id, setting.key, jsonb_build_object('enabled', false, 'hours_before', 3)
from public.organizations o
cross join (
  values
    ('friendly_confirmation_deadline'),
    ('championship_confirmation_deadline')
) as setting(key)
on conflict (organization_id, key) do nothing;

alter table public.training_confirmation_deadline_notifications
  add column if not exists event_type text not null default 'treino';

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
  setting_key text;
  setting_value jsonb;
  enabled boolean := false;
  hours_before integer := 3;
  deadline_at timestamptz;
  event_label text;
begin
  if lower(coalesce(new.status, '')) <> 'accepted' or
     (tg_op = 'UPDATE' and lower(coalesce(old.status, '')) = 'accepted') or
     lower(coalesce(new.event_role, 'athlete')) not in ('athlete', 'atleta') then
    return new;
  end if;

  select
    e.organization_id,
    lower(trim(coalesce(e.event_type, ''))),
    e.event_date::text,
    e.event_time::text
  into event_organization_id, event_type, event_date_text, event_time_text
  from public.events e
  where e.id = new.event_id;

  setting_key := case event_type
    when 'treino' then 'training_confirmation_deadline'
    when 'amistoso' then 'friendly_confirmation_deadline'
    when 'campeonato' then 'championship_confirmation_deadline'
    else null
  end;
  if not found or setting_key is null then return new; end if;

  if auth.uid() is null or public.is_organization_admin(event_organization_id) then
    return new;
  end if;

  select s.value into setting_value
  from public.organization_settings s
  where s.organization_id = event_organization_id
    and s.key = setting_key;

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
    event_label := case event_type
      when 'amistoso' then 'amistoso'
      when 'campeonato' then 'campeonato'
      else 'treino'
    end;
    raise exception using
      errcode = 'P0001',
      message = format(
        'O prazo para confirmar sua presença neste %s expirou. Você não deverá comparecer ao %s.',
        event_label,
        event_label
      );
  end if;
  return new;
end;
$$;

create or replace function public.claim_expired_event_confirmations_v2(
  p_limit integer default 100
)
returns table (
  convocation_id uuid,
  organization_id uuid,
  event_id uuid,
  user_id uuid,
  event_name text,
  event_type text,
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
      coalesce(nullif(trim(e.event_name), ''), initcap(lower(e.event_type))) as event_name,
      lower(trim(e.event_type)) as event_type,
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
     and s.key = case lower(trim(e.event_type))
       when 'treino' then 'training_confirmation_deadline'
       when 'amistoso' then 'friendly_confirmation_deadline'
       when 'campeonato' then 'championship_confirmation_deadline'
       else null
     end
    left join public.training_confirmation_deadline_notifications n
      on n.convocation_id = c.id
    where lower(trim(coalesce(e.event_type, ''))) in ('treino', 'amistoso', 'campeonato')
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
      and (
        n.claimed_at is null or
        n.claimed_at < clock_timestamp() - interval '10 minutes'
      )
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
      event_type,
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
      candidate.event_type,
      candidate.confirmation_deadline_at,
      clock_timestamp(),
      1,
      null
    from candidates candidate
    on conflict on constraint training_confirmation_deadline_notifications_pkey
      do update
      set claimed_at = clock_timestamp(),
          event_type = excluded.event_type,
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
    candidate.event_type,
    candidate.confirmation_deadline_at
  from candidates candidate
  join claimed on claimed.convocation_id = candidate.convocation_id;
end;
$$;

revoke all on function public.claim_expired_event_confirmations_v2(integer) from public;
grant execute on function public.claim_expired_event_confirmations_v2(integer) to service_role;

commit;
