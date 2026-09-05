begin;

create or replace function public.get_monthly_gender_ranking_v3(
  p_gender text,
  p_reference_month integer,
  p_reference_year integer,
  p_previous_month integer,
  p_previous_year integer
)
returns table (
  id uuid,
  name text,
  first_name text,
  avatar_url text,
  total_points bigint,
  presence_count bigint,
  first_checkins bigint,
  earliest_checkin_at timestamptz,
  ranking_position bigint,
  movement text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_organization_id uuid;
  v_gender text;
begin
  if auth.uid() is null then
    return;
  end if;

  v_organization_id := public.current_organization_id();
  if v_organization_id is null
     or not public.is_organization_member(v_organization_id) then
    return;
  end if;

  v_gender := lower(trim(coalesce(p_gender, '')));
  if v_gender not in ('feminino', 'masculino') then
    return;
  end if;

  return query
  with valid_checkins as (
    select
      c.user_id,
      c.event_id,
      coalesce(c.checked_in_at, c.created_at) as checked_at,
      e.event_start_at,
      extract(month from e.event_start_at at time zone 'America/Sao_Paulo')::integer as event_month,
      extract(year from e.event_start_at at time zone 'America/Sao_Paulo')::integer as event_year,
      row_number() over (
        partition by c.user_id, c.event_id
        order by coalesce(c.checked_in_at, c.created_at), c.id
      ) as user_event_order
    from public.checkins c
    join public.events e
      on e.id = c.event_id
     and e.organization_id = v_organization_id
    where c.organization_id = v_organization_id
      and lower(trim(coalesce(e.event_type, ''))) = 'treino'
      and lower(trim(coalesce(c.check_in_status, ''))) = 'realizado'
      and e.event_start_at is not null
      and exists (
        select 1
        from public.profiles eligible_profile
        where eligible_profile.id = c.user_id
          and eligible_profile.organization_id = v_organization_id
          and eligible_profile.is_active is not false
          and lower(trim(coalesce(eligible_profile.gender, ''))) = v_gender
          and (
            lower(trim(coalesce(eligible_profile.user_type, ''))) in ('athlete', 'atleta')
            or exists (
              select 1
              from public.user_roles eligible_role
              where eligible_role.user_id = eligible_profile.id
                and eligible_role.is_active = true
                and lower(trim(coalesce(eligible_role.role, ''))) in ('athlete', 'atleta')
            )
          )
      )
      and coalesce(c.checked_in_at, c.created_at) between
          e.event_start_at - interval '10 minutes'
          and e.event_start_at + interval '30 minutes'
      and (
        (extract(month from e.event_start_at at time zone 'America/Sao_Paulo')::integer = p_reference_month
          and extract(year from e.event_start_at at time zone 'America/Sao_Paulo')::integer = p_reference_year)
        or
        (extract(month from e.event_start_at at time zone 'America/Sao_Paulo')::integer = p_previous_month
          and extract(year from e.event_start_at at time zone 'America/Sao_Paulo')::integer = p_previous_year)
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
  ),
  athlete_scores as (
    select
      p.id,
      coalesce(nullif(trim(p.full_name), ''), 'Atleta') as full_name,
      coalesce(p.avatar_url, '') as avatar_url,
      ra.event_month,
      ra.event_year,
      count(*)::bigint as presence_count,
      count(*) filter (where ra.arrival_position = 1)::bigint as first_checkins,
      min(ra.checked_at) as earliest_checkin_at,
      sum(
        case
          when ra.checked_at <= ra.event_start_at + interval '10 minutes' then 2
          else 1
        end
        + case when ra.arrival_position = 1 then 1 else 0 end
      )::bigint as total_points
    from ranked_arrivals ra
    join public.profiles p
      on p.id = ra.user_id
     and p.organization_id = v_organization_id
     and p.is_active is not false
    where lower(trim(coalesce(p.gender, ''))) = v_gender
      and (
        lower(trim(coalesce(p.user_type, ''))) in ('athlete', 'atleta')
        or exists (
          select 1
          from public.user_roles ur
          where ur.user_id = p.id
            and ur.is_active = true
            and lower(trim(coalesce(ur.role, ''))) in ('athlete', 'atleta')
        )
      )
    group by p.id, p.full_name, p.avatar_url, ra.event_month, ra.event_year
  ),
  current_ranking as (
    select
      scores.*,
      row_number() over (
        order by
          scores.total_points desc,
          scores.earliest_checkin_at asc,
          scores.id
      )::bigint as position
    from athlete_scores scores
    where scores.event_month = p_reference_month
      and scores.event_year = p_reference_year
  ),
  previous_ranking as (
    select
      scores.id,
      row_number() over (
        order by
          scores.total_points desc,
          scores.earliest_checkin_at asc,
          scores.id
      )::bigint as position
    from athlete_scores scores
    where scores.event_month = p_previous_month
      and scores.event_year = p_previous_year
  )
  select
    cur.id,
    cur.full_name as name,
    split_part(cur.full_name, ' ', 1) as first_name,
    cur.avatar_url,
    cur.total_points,
    cur.presence_count,
    cur.first_checkins,
    cur.earliest_checkin_at,
    cur.position as ranking_position,
    case
      when prev.position is null then 'new'
      when cur.position < prev.position then 'up'
      when cur.position > prev.position then 'down'
      else 'same'
    end as movement
  from current_ranking cur
  left join previous_ranking prev on prev.id = cur.id
  order by cur.position;
end;
$$;

revoke all on function public.get_monthly_gender_ranking_v3(
  text, integer, integer, integer, integer
) from public, anon;
grant execute on function public.get_monthly_gender_ranking_v3(
  text, integer, integer, integer, integer
) to authenticated, service_role;

commit;
