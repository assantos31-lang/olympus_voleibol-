-- Olympus / Plataforma de Clubes
-- Auditoria complementar da Fase 7: RPCs estritamente vinculados ao usuario.

begin;

-- Somente funcoes que validam auth.uid(), a participacao do usuario ou a
-- administracao da conversa voltam ao modo otimizado. Consultas administrativas
-- amplas continuam SECURITY INVOKER para que o RLS do clube siga obrigatorio.
alter function public.get_checked_in_training_plan_blocks_for_athlete()
  security definer;
alter function public.get_checked_in_training_plan_blocks_for_athlete()
  set search_path = public, pg_temp;

alter function public.get_event_coaches_for_athlete_evaluation(uuid)
  security definer;
alter function public.get_event_coaches_for_athlete_evaluation(uuid)
  set search_path = public, pg_temp;

alter function public.mark_coach_evaluations_viewed()
  security definer;
alter function public.mark_coach_evaluations_viewed()
  set search_path = public, pg_temp;

alter function public.get_my_financial_access_v1()
  security definer;
alter function public.get_my_financial_access_v1()
  set search_path = public, pg_temp;

alter function public.register_user_push_token(uuid, text, text, text, text)
  security definer;
alter function public.register_user_push_token(uuid, text, text, text, text)
  set search_path = public, pg_temp;

alter function public.add_chat_room_participants_v1(uuid, uuid[])
  security definer;
alter function public.add_chat_room_participants_v1(uuid, uuid[])
  set search_path = public, pg_temp;

alter function public.manage_chat_participant_v1(uuid, uuid, text, text)
  security definer;
alter function public.manage_chat_participant_v1(uuid, uuid, text, text)
  set search_path = public, pg_temp;

revoke all on function public.get_checked_in_training_plan_blocks_for_athlete() from public;
revoke all on function public.get_event_coaches_for_athlete_evaluation(uuid) from public;
revoke all on function public.mark_coach_evaluations_viewed() from public;
revoke all on function public.get_my_financial_access_v1() from public;
revoke all on function public.register_user_push_token(uuid, text, text, text, text) from public;
revoke all on function public.add_chat_room_participants_v1(uuid, uuid[]) from public;
revoke all on function public.manage_chat_participant_v1(uuid, uuid, text, text) from public;

grant execute on function public.get_checked_in_training_plan_blocks_for_athlete()
  to authenticated, service_role;
grant execute on function public.get_event_coaches_for_athlete_evaluation(uuid)
  to authenticated, service_role;
grant execute on function public.mark_coach_evaluations_viewed()
  to authenticated, service_role;
grant execute on function public.get_my_financial_access_v1()
  to authenticated, service_role;
grant execute on function public.register_user_push_token(uuid, text, text, text, text)
  to authenticated, service_role;
grant execute on function public.add_chat_room_participants_v1(uuid, uuid[])
  to authenticated, service_role;
grant execute on function public.manage_chat_participant_v1(uuid, uuid, text, text)
  to authenticated, service_role;

create index if not exists idx_convocations_event_user_status_v2
  on public.convocations (event_id, user_id, status);

create index if not exists idx_checkins_event_user_status_v2
  on public.checkins (event_id, user_id, check_in_status);

create index if not exists idx_training_plan_blocks_event_position_v2
  on public.training_plan_blocks (event_id, position);

create index if not exists idx_coach_evaluations_coach_pending_view_v2
  on public.coach_evaluations (coach_id, visible_to_coach, admin_review_status)
  where coach_viewed_at is null;

create index if not exists idx_financial_records_athlete_status_v2
  on public.financial_records (athlete_id, type, status, year, month);

create index if not exists idx_user_push_tokens_user_seen_v2
  on public.user_push_tokens (user_id, last_seen_at desc);

commit;
