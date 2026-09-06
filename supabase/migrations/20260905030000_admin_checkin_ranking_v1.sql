begin;

create or replace function public.get_admin_checkin_ranking_v1(
  p_start_date date,
  p_end_date date
)
returns table (
  id uuid,
  name text,
  avatar_url text,
  gender text,
  court_position text,
  total_points bigint,
  presence_count bigint,
  first_checkins bigint,
  earliest_checkin_at timestamptz,
  training_days date[],
  checkin_ids uuid[]
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_organization_id uuid;
begin
  if auth.uid() is null
     or p_start_date is null
     or p_end_date is null
     or p_end_date < p_start_date then
    return;
  end if;

  v_organization_id := public.current_organization_id();
  if v_organization_id is null
     or not public.is_organization_admin(v_organization_id) then
    return;
  end if;

  return query
  with valid_checkins as (
    select
      c.id as checkin_id,
      c.user_id,
      c.event_id,
      public.resolve_effective_checkin_at(
        c.checked_in_at,
        c.created_at,
        e.event_start_at
      ) as checked_at,
      e.event_start_at,
      (e.event_start_at at time zone 'America/Sao_Paulo')::date as training_day,
      row_number() over (
        partition by c.user_id, c.event_id
        order by
          public.resolve_effective_checkin_at(
            c.checked_in_at,
            c.created_at,
            e.event_start_at
          ),
          c.id
      ) as user_event_order
    from public.checkins c
    join public.events e
      on e.id = c.event_id
     and e.organization_id = v_organization_id
    where c.organization_id = v_organization_id
      and (
        trim(coalesce(e.event_type, '')) = ''
        or lower(trim(e.event_type)) = 'training'
        or position('treino' in lower(trim(e.event_type))) > 0
      )
      and lower(trim(coalesce(c.check_in_status, ''))) in (
        'realizado',
        'realizado com sucesso',
        'checked_in',
        'checkin_realizado',
        'check-in realizado',
        'presente',
        'presence',
        'ok',
        'success',
        'completed',
        'done',
        'manual',
        'late',
        'atrasado',
        'checkin_atrasado'
      )
      and e.event_start_at is not null
      and (e.event_start_at at time zone 'America/Sao_Paulo')::date
          between p_start_date and p_end_date
      and public.resolve_effective_checkin_at(
            c.checked_in_at,
            c.created_at,
            e.event_start_at
          ) between
          e.event_start_at - interval '10 minutes'
          and e.event_start_at + interval '30 minutes'
      and exists (
        select 1
        from public.profiles eligible_profile
        where eligible_profile.id = c.user_id
          and eligible_profile.organization_id = v_organization_id
          and eligible_profile.is_active is not false
          and (
            lower(trim(coalesce(eligible_profile.user_type, ''))) in
              ('athlete', 'atleta')
            or exists (
              select 1
              from public.user_roles eligible_role
              where eligible_role.user_id = eligible_profile.id
                and eligible_role.organization_id = v_organization_id
                and eligible_role.is_active = true
                and lower(trim(coalesce(eligible_role.role, ''))) in
                  ('athlete', 'atleta')
            )
          )
      )
  ),
  one_checkin_per_user_event as (
    select *
    from valid_checkins
    where user_event_order = 1
  ),
  ranked_arrivals as (
    select
      vc.*,
      row_number() over (
        partition by vc.event_id
        order by vc.checked_at, vc.user_id
      ) as arrival_position
    from one_checkin_per_user_event vc
  )
  select
    profile.id,
    coalesce(nullif(trim(profile.full_name), ''), 'Atleta')::text as name,
    coalesce(profile.avatar_url, '')::text as avatar_url,
    coalesce(profile.gender, '')::text as gender,
    coalesce(profile.court_position, '')::text as court_position,
    sum(
      case
        when arrival.checked_at <= arrival.event_start_at + interval '10 minutes'
          then 2
        else 1
      end
      + case when arrival.arrival_position = 1 then 1 else 0 end
    )::bigint as total_points,
    count(*)::bigint as presence_count,
    count(*) filter (where arrival.arrival_position = 1)::bigint
      as first_checkins,
    min(arrival.checked_at) as earliest_checkin_at,
    array_agg(distinct arrival.training_day order by arrival.training_day)
      as training_days,
    array_agg(
      arrival.checkin_id
      order by arrival.checked_at, arrival.checkin_id
    ) as checkin_ids
  from ranked_arrivals arrival
  join public.profiles profile
    on profile.id = arrival.user_id
   and profile.organization_id = v_organization_id
   and profile.is_active is not false
  group by
    profile.id,
    profile.full_name,
    profile.avatar_url,
    profile.gender,
    profile.court_position
  order by 6 desc, 9 asc, profile.id;
end;
$$;

revoke all on function public.get_admin_checkin_ranking_v1(date, date)
  from public, anon;
grant execute on function public.get_admin_checkin_ranking_v1(date, date)
  to authenticated, service_role;

commit;
