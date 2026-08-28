begin;

-- As views passam a respeitar as permissões e o RLS do usuário que consulta,
-- em vez de executar com os privilégios do proprietário da view.
alter view public.event_convocation_stats set (security_invoker = true);
alter view public.eligible_for_checkin set (security_invoker = true);

-- Tabelas internas não fazem parte da API do aplicativo. Com RLS habilitado e
-- sem políticas públicas, somente conexões administrativas/service_role podem
-- acessá-las.
alter table public.page_permissions_backup enable row level security;
alter table public.trigger_debug_logs enable row level security;
revoke all on table public.page_permissions_backup from anon, authenticated;
revoke all on table public.trigger_debug_logs from anon, authenticated;

commit;
