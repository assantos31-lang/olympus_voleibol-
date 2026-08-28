begin;

-- A instalação deve acompanhar o clube do usuário autenticado. Antes desta
-- correção, a coluna recebia o clube Olympus por padrão e não era atualizada
-- quando o mesmo aparelho entrava em uma conta de outro clube.
create or replace function public.register_user_push_token(
  p_installation_id uuid,
  p_device_token text,
  p_platform text,
  p_permission_status text default null,
  p_app_version text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_user_id uuid := auth.uid();
  v_organization_id uuid;
  v_now timestamptz := now();
begin
  if v_user_id is null then
    raise exception 'Usuário não autenticado.';
  end if;

  select p.organization_id
    into v_organization_id
  from public.profiles p
  where p.id = v_user_id;

  if v_organization_id is null then
    raise exception 'Usuário sem clube ativo.';
  end if;

  if not exists (
    select 1
    from public.organization_members om
    where om.organization_id = v_organization_id
      and om.user_id = v_user_id
      and om.status = 'active'
  ) then
    raise exception 'Vínculo ativo com o clube não encontrado.';
  end if;

  -- Um token FCM representa um único aparelho/usuário ativo. Remove vínculos
  -- antigos deixados por logout ou reinstalação para impedir notificações
  -- cruzadas entre contas e clubes no mesmo telefone.
  delete from public.user_push_tokens
  where device_token = p_device_token
    and installation_id <> p_installation_id;

  update public.profiles
  set push_token = null,
      updated_at = v_now
  where id <> v_user_id
    and push_token = p_device_token;

  insert into public.user_push_tokens (
    installation_id,
    user_id,
    organization_id,
    device_token,
    platform,
    permission_status,
    app_version,
    last_seen_at,
    updated_at,
    created_at
  ) values (
    p_installation_id,
    v_user_id,
    v_organization_id,
    p_device_token,
    p_platform,
    p_permission_status,
    p_app_version,
    v_now,
    v_now,
    v_now
  )
  on conflict (installation_id) do update set
    user_id = excluded.user_id,
    organization_id = excluded.organization_id,
    device_token = excluded.device_token,
    platform = excluded.platform,
    permission_status = excluded.permission_status,
    app_version = excluded.app_version,
    last_seen_at = v_now,
    updated_at = v_now;

  update public.profiles
  set push_token = p_device_token,
      updated_at = v_now
  where id = v_user_id;
end;
$function$;

revoke all on function public.register_user_push_token(uuid, text, text, text, text)
  from public;
grant execute on function public.register_user_push_token(uuid, text, text, text, text)
  to authenticated, service_role;

-- Repara os aparelhos já registrados usando o clube atual do perfil.
update public.user_push_tokens upt
set organization_id = p.organization_id,
    updated_at = now()
from public.profiles p
where p.id = upt.user_id
  and p.organization_id is not null
  and upt.organization_id is distinct from p.organization_id;

create index if not exists idx_user_push_tokens_org_user_seen
  on public.user_push_tokens (organization_id, user_id, last_seen_at desc)
  where user_id is not null;

commit;
