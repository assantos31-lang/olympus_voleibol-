-- Olympus / Plataforma de Clubes
-- Fase 7A: identificacao de todos os dados por clube.
-- Migracao aditiva e idempotente. Os dados existentes permanecem no Olympus.

begin;

create table if not exists public.tenant_isolation_catalog (
  table_name text primary key,
  isolation_mode text not null default 'tagged'
    check (isolation_mode in ('tagged', 'enforced')),
  organization_column text not null default 'organization_id',
  updated_at timestamptz not null default now()
);

alter table public.tenant_isolation_catalog enable row level security;
revoke all on table public.tenant_isolation_catalog from anon, authenticated;

create or replace function public.tenant_target_tables_v1()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array[
    'admin_password_resets',
    'app_message_threads',
    'app_message_participants',
    'app_messages',
    'app_message_hidden',
    'app_message_schedules',
    'app_settings',
    'events',
    'convocations',
    'checkins',
    'checkin_notification_log',
    'event_photos',
    'event_results',
    'event_result_sets',
    'event_rides',
    'geocode_jobs',
    'training_plan_blocks',
    'training_plan_notes',
    'training_evaluations',
    'coach_evaluations',
    'match_scouts',
    'match_scout_action_details',
    'athlete_monthly_history',
    'ranking_settings',
    'athlete_coach_evaluation_reminder_log',
    'athlete_presence_admin_alert_log',
    'athlete_presence_alert_log',
    'athlete_training_presence_alert_log',
    'coach_training_reminder_log',
    'chat_rooms',
    'chat_room_members',
    'chat_room_hidden_users',
    'chat_messages',
    'chat_message_deliveries',
    'chat_message_reads',
    'chat_message_reactions',
    'chat_pinned_messages',
    'chat_polls',
    'chat_poll_options',
    'chat_poll_votes',
    'chat_typing_status',
    'financial_records',
    'financial_access_settings',
    'financial_training_blocks',
    'page_permissions',
    'user_presence',
    'user_push_tokens',
    'user_saved_stickers'
  ]::text[]
$$;

-- Primeiro adiciona e preenche as colunas. Isto ocorre antes dos gatilhos para
-- que todas as tabelas relacionadas ja estejam preparadas quando eles iniciarem.
do $$
declare
  target_table text;
  target_regclass regclass;
  organization_attnum smallint;
  constraint_name text;
begin
  foreach target_table in array public.tenant_target_tables_v1() loop
    target_regclass := to_regclass(format('public.%I', target_table));
    if target_regclass is null then
      continue;
    end if;

    execute format(
      'alter table public.%I add column if not exists organization_id uuid',
      target_table
    );

    execute format(
      'update public.%I set organization_id = public.default_organization_id() where organization_id is null',
      target_table
    );

    execute format(
      'alter table public.%I alter column organization_id set not null',
      target_table
    );

    select a.attnum
    into organization_attnum
    from pg_attribute a
    where a.attrelid = target_regclass
      and a.attname = 'organization_id'
      and not a.attisdropped;

    if not exists (
      select 1
      from pg_constraint c
      where c.conrelid = target_regclass
        and c.contype = 'f'
        and organization_attnum = any(c.conkey)
    ) then
      constraint_name := left(target_table || '_organization_id_fkey_v1', 63);
      execute format(
        'alter table public.%I add constraint %I foreign key (organization_id) references public.organizations(id) on delete restrict',
        target_table,
        constraint_name
      );
    end if;

    execute format(
      'create index if not exists %I on public.%I (organization_id)',
      left(target_table || '_organization_id_idx_v1', 63),
      target_table
    );

    insert into public.tenant_isolation_catalog (
      table_name,
      isolation_mode,
      updated_at
    ) values (target_table, 'tagged', now())
    on conflict (table_name) do update
    set updated_at = excluded.updated_at;
  end loop;
end;
$$;

create or replace function public.resolve_tenant_organization_v1(
  payload jsonb
)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  resolved uuid;
  reference_id uuid;
begin
  resolved := public.current_organization_id();
  if resolved is not null then
    return resolved;
  end if;

  reference_id := nullif(payload ->> 'event_id', '')::uuid;
  if reference_id is not null then
    select e.organization_id into resolved
    from public.events e where e.id = reference_id;
  end if;

  if resolved is null then
    reference_id := nullif(payload ->> 'room_id', '')::uuid;
    if reference_id is not null then
      select r.organization_id into resolved
      from public.chat_rooms r where r.id = reference_id;
    end if;
  end if;

  if resolved is null then
    reference_id := nullif(payload ->> 'message_id', '')::uuid;
    if reference_id is not null then
      select m.organization_id into resolved
      from public.chat_messages m where m.id = reference_id;
    end if;
  end if;

  if resolved is null then
    reference_id := nullif(payload ->> 'thread_id', '')::uuid;
    if reference_id is not null then
      select t.organization_id into resolved
      from public.app_message_threads t where t.id = reference_id;
    end if;
  end if;

  if resolved is null then
    reference_id := nullif(payload ->> 'poll_id', '')::uuid;
    if reference_id is not null then
      select p.organization_id into resolved
      from public.chat_polls p where p.id = reference_id;
    end if;
  end if;

  if resolved is null then
    reference_id := nullif(payload ->> 'option_id', '')::uuid;
    if reference_id is not null then
      select o.organization_id into resolved
      from public.chat_poll_options o where o.id = reference_id;
    end if;
  end if;

  if resolved is null then
    reference_id := nullif(payload ->> 'event_result_id', '')::uuid;
    if reference_id is not null then
      select er.organization_id into resolved
      from public.event_results er where er.id = reference_id;
    end if;
  end if;

  if resolved is null then
    reference_id := coalesce(
      nullif(payload ->> 'user_id', '')::uuid,
      nullif(payload ->> 'athlete_id', '')::uuid,
      nullif(payload ->> 'coach_id', '')::uuid,
      nullif(payload ->> 'created_by', '')::uuid
    );
    if reference_id is not null then
      select p.organization_id into resolved
      from public.profiles p where p.id = reference_id;
    end if;
  end if;

  return coalesce(resolved, public.default_organization_id());
end;
$$;

create or replace function public.assign_tenant_organization_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  resolved uuid;
  service_context boolean;
begin
  service_context := auth.uid() is null
    and coalesce(auth.role(), '') <> 'anon';

  if tg_op = 'UPDATE'
     and old.organization_id is distinct from new.organization_id
     and not service_context
     and not public.is_platform_admin_v1() then
    raise exception 'O clube de um registro existente nao pode ser alterado.';
  end if;

  resolved := coalesce(
    new.organization_id,
    public.resolve_tenant_organization_v1(to_jsonb(new))
  );

  if resolved is null then
    raise exception 'Nao foi possivel identificar o clube do registro.';
  end if;

  if not service_context
     and not public.is_platform_admin_v1()
     and not public.is_organization_member(resolved) then
    raise exception 'Usuario nao pertence ao clube informado.';
  end if;

  new.organization_id := resolved;
  return new;
end;
$$;

do $$
declare
  target_table text;
begin
  foreach target_table in array public.tenant_target_tables_v1() loop
    if to_regclass(format('public.%I', target_table)) is null then
      continue;
    end if;

    execute format(
      'drop trigger if exists tenant_assign_organization_v1 on public.%I',
      target_table
    );
    execute format(
      'create trigger tenant_assign_organization_v1 before insert or update on public.%I for each row execute function public.assign_tenant_organization_v1()',
      target_table
    );
  end loop;
end;
$$;

create or replace function public.tenant_tagging_audit_v1()
returns table (
  table_name text,
  total_rows bigint,
  missing_organization_rows bigint,
  distinct_organizations bigint
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_table text;
begin
  foreach target_table in array public.tenant_target_tables_v1() loop
    if to_regclass(format('public.%I', target_table)) is null then
      continue;
    end if;

    return query execute format(
      'select %L::text, count(*)::bigint, count(*) filter (where organization_id is null)::bigint, count(distinct organization_id)::bigint from public.%I',
      target_table,
      target_table
    );
  end loop;
end;
$$;

revoke all on function public.tenant_target_tables_v1() from public;
revoke all on function public.resolve_tenant_organization_v1(jsonb) from public;
revoke all on function public.assign_tenant_organization_v1() from public;
revoke all on function public.tenant_tagging_audit_v1() from public;
grant execute on function public.tenant_tagging_audit_v1() to service_role;

commit;
