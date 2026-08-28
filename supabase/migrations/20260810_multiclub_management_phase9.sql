-- Olympus / Plataforma de Clubes
-- Fase 9: gestao de convites, usuarios e indicadores do Admin Master.
-- Requer a Fase 8. Idempotente e sem alterar dados do Olympus.

begin;

create or replace function public.platform_organization_dashboard_v1()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when not public.is_platform_admin_v1() then
      jsonb_build_object('error', 'Acesso restrito ao Admin Master')
    else coalesce(
      jsonb_object_agg(
        o.id::text,
        jsonb_build_object(
          'user_count', coalesce(m.user_count, 0),
          'admin_count', coalesce(m.admin_count, 0),
          'invitation', coalesce(i.invitation, 'null'::jsonb)
        )
      ),
      '{}'::jsonb
    )
  end
  from public.organizations o
  left join lateral (
    select
      count(*) filter (where om.status = 'active')::integer as user_count,
      count(*) filter (
        where om.status = 'active' and om.role in ('owner', 'admin')
      )::integer as admin_count
    from public.organization_members om
    where om.organization_id = o.id
  ) m on true
  left join lateral (
    select jsonb_build_object(
      'id', x.id,
      'email', x.email,
      'status', x.status,
      'expires_at', x.expires_at,
      'created_at', x.created_at,
      'accepted_at', x.accepted_at
    ) as invitation
    from public.organization_admin_invitations x
    where x.organization_id = o.id
    order by
      case x.status when 'pending' then 0 when 'accepted' then 1 else 2 end,
      x.created_at desc
    limit 1
  ) i on true;
$$;

create or replace function public.platform_cancel_admin_invitation_v1(
  p_invitation_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_platform_admin_v1() then
    raise exception 'Acesso restrito ao Admin Master' using errcode = '42501';
  end if;

  update public.organization_admin_invitations
  set status = 'cancelled', updated_at = now()
  where id = p_invitation_id and status in ('pending', 'expired');

  if not found then
    raise exception 'Convite nao encontrado ou ja utilizado';
  end if;
end;
$$;

create or replace function public.platform_renew_admin_invitation_v1(
  p_invitation_id uuid,
  p_days integer default 30
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  updated_invite public.organization_admin_invitations%rowtype;
begin
  if not public.is_platform_admin_v1() then
    raise exception 'Acesso restrito ao Admin Master' using errcode = '42501';
  end if;

  update public.organization_admin_invitations
  set status = 'pending',
      expires_at = now() + make_interval(days => greatest(1, least(coalesce(p_days, 30), 90))),
      accepted_by = null,
      accepted_at = null,
      updated_at = now()
  where id = p_invitation_id and status in ('pending', 'expired', 'cancelled')
  returning * into updated_invite;

  if not found then
    raise exception 'Convite nao encontrado ou ja aceito';
  end if;

  return jsonb_build_object(
    'id', updated_invite.id,
    'email', updated_invite.email,
    'status', updated_invite.status,
    'expires_at', updated_invite.expires_at
  );
end;
$$;

create or replace function public.platform_replace_admin_invitation_v1(
  p_organization_id uuid,
  p_admin_email text,
  p_days integer default 30
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_email text := lower(trim(coalesce(p_admin_email, '')));
  new_invite public.organization_admin_invitations%rowtype;
begin
  if not public.is_platform_admin_v1() then
    raise exception 'Acesso restrito ao Admin Master' using errcode = '42501';
  end if;
  if not exists (select 1 from public.organizations o where o.id = p_organization_id) then
    raise exception 'Clube nao encontrado';
  end if;
  if clean_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'Informe um e-mail valido';
  end if;
  if exists (
    select 1 from auth.users au where lower(trim(coalesce(au.email, ''))) = clean_email
  ) then
    raise exception 'Este e-mail ja possui conta no aplicativo';
  end if;
  if exists (
    select 1 from public.organization_admin_invitations i
    where i.email_normalized = clean_email
      and i.status = 'pending'
      and i.organization_id <> p_organization_id
  ) then
    raise exception 'Este e-mail possui convite ativo para outro clube';
  end if;

  update public.organization_admin_invitations
  set status = 'cancelled', updated_at = now()
  where organization_id = p_organization_id and status = 'pending';

  insert into public.organization_admin_invitations (
    organization_id, email, email_normalized, role, status,
    expires_at, created_by
  ) values (
    p_organization_id, clean_email, clean_email, 'admin', 'pending',
    now() + make_interval(days => greatest(1, least(coalesce(p_days, 30), 90))),
    auth.uid()
  ) returning * into new_invite;

  return jsonb_build_object(
    'id', new_invite.id,
    'email', new_invite.email,
    'status', new_invite.status,
    'expires_at', new_invite.expires_at
  );
end;
$$;

revoke all on function public.platform_organization_dashboard_v1() from public;
revoke all on function public.platform_cancel_admin_invitation_v1(uuid) from public;
revoke all on function public.platform_renew_admin_invitation_v1(uuid, integer) from public;
revoke all on function public.platform_replace_admin_invitation_v1(uuid, text, integer) from public;

grant execute on function public.platform_organization_dashboard_v1()
  to authenticated, service_role;
grant execute on function public.platform_cancel_admin_invitation_v1(uuid)
  to authenticated, service_role;
grant execute on function public.platform_renew_admin_invitation_v1(uuid, integer)
  to authenticated, service_role;
grant execute on function public.platform_replace_admin_invitation_v1(uuid, text, integer)
  to authenticated, service_role;

commit;
