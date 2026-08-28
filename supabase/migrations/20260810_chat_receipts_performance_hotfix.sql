-- Olympus / Plataforma de Clubes
-- Correcao urgente do Chat apos a Fase 7.
-- Mantem o isolamento por clube, mas devolve aos RPCs de Chat o contexto
-- otimizado necessario para registrar entrega/leitura e consultar recibos.

begin;

-- Estas funcoes validam auth.uid() e a participacao do proprio usuario na
-- conversa. Como SECURITY DEFINER, conseguem inserir os recibos sem depender
-- de politicas RLS recursivas e continuam limitadas ao usuario autenticado.
alter function public.mark_my_chat_messages_delivered_v1(uuid)
  security definer;
alter function public.mark_my_chat_messages_delivered_v1(uuid)
  set search_path = public, pg_temp;

alter function public.mark_my_chat_room_read_v1(uuid)
  security definer;
alter function public.mark_my_chat_room_read_v1(uuid)
  set search_path = public, pg_temp;

alter function public.get_chat_message_receipt_counts_v1(uuid)
  security definer;
alter function public.get_chat_message_receipt_counts_v1(uuid)
  set search_path = public, pg_temp;

alter function public.get_chat_message_read_status_v1(uuid)
  security definer;
alter function public.get_chat_message_read_status_v1(uuid)
  set search_path = public, pg_temp;

alter function public.get_my_chat_room_list_v1()
  security definer;
alter function public.get_my_chat_room_list_v1()
  set search_path = public, pg_temp;

alter function public.get_my_chat_unread_total_v1()
  security definer;
alter function public.get_my_chat_unread_total_v1()
  set search_path = public, pg_temp;

-- Evita que os RPCs sejam chamados por usuarios anonimos e preserva o uso
-- normal pelos aplicativos autenticados e pelo backend.
revoke all on function public.mark_my_chat_messages_delivered_v1(uuid) from public;
revoke all on function public.mark_my_chat_room_read_v1(uuid) from public;
revoke all on function public.get_chat_message_receipt_counts_v1(uuid) from public;
revoke all on function public.get_chat_message_read_status_v1(uuid) from public;
revoke all on function public.get_my_chat_room_list_v1() from public;
revoke all on function public.get_my_chat_unread_total_v1() from public;

grant execute on function public.mark_my_chat_messages_delivered_v1(uuid)
  to authenticated, service_role;
grant execute on function public.mark_my_chat_room_read_v1(uuid)
  to authenticated, service_role;
grant execute on function public.get_chat_message_receipt_counts_v1(uuid)
  to authenticated, service_role;
grant execute on function public.get_chat_message_read_status_v1(uuid)
  to authenticated, service_role;
grant execute on function public.get_my_chat_room_list_v1()
  to authenticated, service_role;
grant execute on function public.get_my_chat_unread_total_v1()
  to authenticated, service_role;

-- Indices das rotas mais frequentes: abrir conversa, buscar ultima mensagem,
-- atualizar badge e contar entrega/leitura.
create index if not exists idx_chat_messages_room_created_active_v2
  on public.chat_messages (room_id, created_at desc)
  where deleted_at is null;

create index if not exists idx_chat_messages_sender_room_active_v2
  on public.chat_messages (sender_id, room_id, created_at desc)
  where deleted_at is null;

create index if not exists idx_chat_room_members_user_room_active_v2
  on public.chat_room_members (user_id, room_id)
  where coalesce(is_banned, false) = false;

create index if not exists idx_chat_message_deliveries_message_user_v2
  on public.chat_message_deliveries (message_id, user_id);

create index if not exists idx_chat_message_reads_message_user_v2
  on public.chat_message_reads (message_id, user_id);

create index if not exists idx_chat_message_reads_user_message_v2
  on public.chat_message_reads (user_id, message_id);

commit;
