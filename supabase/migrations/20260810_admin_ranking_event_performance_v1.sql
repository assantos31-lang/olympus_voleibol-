-- Olympus: ranking administrativo e abertura mais rápida dos convocados.
-- Apenas índices. Não altera nem remove dados.

begin;

create index if not exists idx_events_org_date_ranking_v1
  on public.events (organization_id, event_date, id);

create index if not exists idx_events_org_start_ranking_v1
  on public.events (organization_id, event_start_at, id);

create index if not exists idx_checkins_org_event_user_status_v1
  on public.checkins (organization_id, event_id, user_id, check_in_status);

create index if not exists idx_convocations_org_event_role_v1
  on public.convocations (organization_id, event_id, event_role, user_id);

commit;
