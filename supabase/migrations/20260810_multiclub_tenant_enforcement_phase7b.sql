-- Olympus / Plataforma de Clubes
-- Fase 7B: isolamento restritivo e execucao dos RPCs no contexto do usuario.
-- Requer a Fase 7A aplicada e validada.

begin;

create or replace function public.can_access_tenant_v1(
  target_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_platform_admin_v1()
    or public.is_organization_member(target_organization_id)
$$;

create or replace function public.can_admin_tenant_v1(
  target_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_platform_admin_v1()
    or public.is_organization_admin(target_organization_id)
$$;

create or replace function public.referenced_tenant_organization_v1(
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
  reference_id := coalesce(
    nullif(payload ->> 'event_id', '')::uuid,
    nullif(payload ->> 'related_event_id', '')::uuid
  );
  if reference_id is not null then
    select e.organization_id into resolved
    from public.events e where e.id = reference_id;
  end if;

  if resolved is null then
    reference_id := nullif(payload ->> 'related_convocation_id', '')::uuid;
    if reference_id is not null then
      select c.organization_id into resolved
      from public.convocations c where c.id = reference_id;
    end if;
  end if;

  if resolved is null then
    reference_id := nullif(payload ->> 'room_id', '')::uuid;
    if reference_id is not null then
      select r.organization_id into resolved
      from public.chat_rooms r where r.id = reference_id;
    end if;
  end if;

  if resolved is null then
    reference_id := coalesce(
      nullif(payload ->> 'message_id', '')::uuid,
      nullif(payload ->> 'reply_to_message_id', '')::uuid
    );
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
      nullif(payload ->> 'created_by', '')::uuid,
      nullif(payload ->> 'sender_id', '')::uuid
    );
    if reference_id is not null then
      select p.organization_id into resolved
      from public.profiles p where p.id = reference_id;
    end if;
  end if;

  return resolved;
end;
$$;

create or replace function public.resolve_tenant_organization_v1(
  payload jsonb
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    public.referenced_tenant_organization_v1(payload),
    public.current_organization_id(),
    public.default_organization_id()
  )
$$;

create or replace function public.assert_tenant_references_v1(
  payload jsonb,
  target_organization_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  referenced_organization_id uuid;
  reference_id uuid;
  reference_key text;
begin
  referenced_organization_id :=
    public.referenced_tenant_organization_v1(payload);
  if referenced_organization_id is not null
     and referenced_organization_id <> target_organization_id then
    raise exception 'O registro relacionado pertence a outro clube.';
  end if;

  foreach reference_key in array array[
    'user_id',
    'athlete_id',
    'coach_id',
    'created_by',
    'sender_id',
    'updated_by',
    'approved_by',
    'pinned_by'
  ] loop
    reference_id := nullif(payload ->> reference_key, '')::uuid;
    if reference_id is null then
      continue;
    end if;

    if exists (select 1 from public.profiles p where p.id = reference_id)
       and not exists (
         select 1 from public.profiles p
         where p.id = reference_id
           and p.organization_id = target_organization_id
       ) then
      raise exception 'O usuario relacionado pertence a outro clube.';
    end if;
  end loop;
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

  perform public.assert_tenant_references_v1(to_jsonb(new), resolved);

  if not service_context
     and not public.is_platform_admin_v1()
     and not public.is_organization_member(resolved) then
    raise exception 'Usuario nao pertence ao clube informado.';
  end if;

  new.organization_id := resolved;
  return new;
end;
$$;

-- As politicas restritivas trabalham em conjunto com as politicas atuais.
-- Portanto elas reduzem o alcance ao clube sem ampliar permissoes funcionais.
do $$
declare
  target_table text;
begin
  foreach target_table in array array_cat(
    public.tenant_target_tables_v1(),
    array['profiles', 'user_profiles', 'user_roles']::text[]
  ) loop
    if to_regclass(format('public.%I', target_table)) is null then
      continue;
    end if;

    execute format('alter table public.%I enable row level security', target_table);
    execute format(
      'drop policy if exists tenant_organization_restrictive_v1 on public.%I',
      target_table
    );
    execute format(
      'create policy tenant_organization_restrictive_v1 on public.%I as restrictive for all to authenticated using (public.can_access_tenant_v1(organization_id)) with check (public.can_access_tenant_v1(organization_id))',
      target_table
    );
  end loop;
end;
$$;

-- Estas tabelas eram acessadas diretamente pelo aplicativo e nao possuiam
-- politica permissiva propria. A permissao abaixo preserva o uso somente para
-- membros do mesmo clube; a politica restritiva acima continua obrigatoria.
do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'app_message_hidden',
    'app_message_schedules',
    'athlete_monthly_history',
    'ranking_settings',
    'geocode_jobs'
  ] loop
    if to_regclass(format('public.%I', target_table)) is null then
      continue;
    end if;

    execute format(
      'drop policy if exists tenant_member_base_v1 on public.%I',
      target_table
    );
    execute format(
      'create policy tenant_member_base_v1 on public.%I for all to authenticated using (public.is_organization_member(organization_id)) with check (public.is_organization_member(organization_id))',
      target_table
    );
  end loop;
end;
$$;

-- Os RPCs chamados pelo Flutter deixam de executar como uma funcao que ignora
-- RLS. O codigo e as assinaturas permanecem iguais; apenas o contexto passa a
-- ser o usuario autenticado, respeitando todas as politicas da tabela.
do $$
declare
  function_name text;
  function_record record;
begin
  foreach function_name in array array[
    'mark_my_chat_messages_delivered_v1',
    'get_checked_in_athletes_for_event',
    'get_checked_in_training_plan_blocks_for_athlete',
    'mark_coach_evaluations_viewed',
    'get_agenda_event_convocados',
    'do_checkin',
    'get_monthly_gender_ranking',
    'get_event_coaches_for_athlete_evaluation',
    'get_my_chat_room_list_v1',
    'get_my_chat_unread_total_v1',
    'get_chat_message_receipt_counts_v1',
    'mark_my_chat_room_read_v1',
    'get_chat_message_read_status_v1',
    'add_chat_room_participants_v1',
    'manage_chat_participant_v1',
    'get_my_first_pending_poll_room_v1',
    'get_my_financial_access_v1',
    'list_overdue_athlete_blocks_v1',
    'set_overdue_athlete_block_v1',
    'register_user_push_token'
  ] loop
    for function_record in
      select p.oid::regprocedure as signature
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname = function_name
    loop
      execute format(
        'alter function %s security invoker',
        function_record.signature
      );
    end loop;
  end loop;
end;
$$;

update public.tenant_isolation_catalog
set isolation_mode = 'enforced',
    updated_at = now()
where table_name = any(public.tenant_target_tables_v1());

revoke all on function public.can_access_tenant_v1(uuid) from public;
revoke all on function public.can_admin_tenant_v1(uuid) from public;
revoke all on function public.referenced_tenant_organization_v1(jsonb) from public;
revoke all on function public.assert_tenant_references_v1(jsonb, uuid) from public;
grant execute on function public.can_access_tenant_v1(uuid) to authenticated, service_role;
grant execute on function public.can_admin_tenant_v1(uuid) to authenticated, service_role;

commit;
