begin;

-- New/manual records use checked_in_at. Some legacy admin records stored the
-- informed America/Sao_Paulo wall-clock in created_at while marking it as UTC.
-- Resolve that historical representation only when the +03:00 correction
-- lands inside the unchanged ranking window for the linked event.
create or replace function public.resolve_effective_checkin_at(
  p_checked_in_at timestamptz,
  p_created_at timestamptz,
  p_event_start_at timestamptz
)
returns timestamptz
language sql
immutable
set search_path = ''
as $$
  select case
    when p_checked_in_at is not null then p_checked_in_at
    when p_created_at between
        p_event_start_at - interval '10 minutes'
        and p_event_start_at + interval '30 minutes'
      then p_created_at
    when p_created_at + interval '3 hours' between
        p_event_start_at - interval '10 minutes'
        and p_event_start_at + interval '30 minutes'
      then p_created_at + interval '3 hours'
    else p_created_at
  end;
$$;

-- Reuse the already deployed v3 function definition and change only the
-- timestamp resolver. This leaves points, ranking order and visibility intact.
do $migration$
declare
  v_definition text;
  v_original text := 'coalesce(c.checked_in_at, c.created_at)';
  v_replacement text := 'public.resolve_effective_checkin_at(c.checked_in_at, c.created_at, e.event_start_at)';
begin
  select pg_get_functiondef(
    'public.get_monthly_gender_ranking_v3(text,integer,integer,integer,integer)'::regprocedure
  ) into v_definition;

  if strpos(v_definition, v_original) = 0 then
    raise exception 'Expected timestamp expression was not found in ranking v3';
  end if;

  execute replace(v_definition, v_original, v_replacement);
end;
$migration$;

revoke all on function public.resolve_effective_checkin_at(
  timestamptz, timestamptz, timestamptz
) from public, anon;
grant execute on function public.resolve_effective_checkin_at(
  timestamptz, timestamptz, timestamptz
) to authenticated, service_role;

commit;
