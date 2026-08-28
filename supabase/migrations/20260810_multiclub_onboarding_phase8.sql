-- Olympus / Plataforma de Clubes
-- Fase 8: onboarding completo e seguro de clubes pelo Admin Master.
-- Compativel com as fases anteriores e sem alterar o clube Olympus.

begin;

create table if not exists public.organization_admin_invitations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references public.organizations(id) on delete cascade,
  email text not null,
  email_normalized text not null,
  role text not null default 'admin'
    check (role in ('owner', 'admin')),
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'cancelled', 'expired')),
  expires_at timestamptz not null default (now() + interval '30 days'),
  created_by uuid references auth.users(id) on delete set null,
  accepted_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  updated_at timestamptz not null default now()
);

create unique index if not exists organization_admin_invites_pending_email_idx
  on public.organization_admin_invitations (email_normalized)
  where status = 'pending';

create index if not exists organization_admin_invites_org_idx
  on public.organization_admin_invitations (organization_id, status, created_at desc);

alter table public.organization_admin_invitations enable row level security;

drop policy if exists organization_admin_invites_master_select_v1
  on public.organization_admin_invitations;
create policy organization_admin_invites_master_select_v1
on public.organization_admin_invitations for select to authenticated
using (public.is_platform_admin_v1());

revoke all on public.organization_admin_invitations from public, anon, authenticated;
grant select on public.organization_admin_invitations to authenticated;

create or replace function public.platform_onboard_organization_v2(
  p_name text,
  p_slug text,
  p_plan_code text default 'professional',
  p_max_users integer default 100,
  p_admin_email text default null,
  p_enabled_features text[] default null,
  p_branding jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_id uuid;
  invitation_id uuid;
  clean_email text := lower(trim(coalesce(p_admin_email, '')));
  clean_branding jsonb;
  selected_features text[] := coalesce(p_enabled_features, array[]::text[]);
begin
  if not public.is_platform_admin_v1() then
    raise exception 'Acesso restrito ao Admin Master' using errcode = '42501';
  end if;

  if clean_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'Informe um e-mail valido para o primeiro administrador';
  end if;

  if exists (
    select 1 from auth.users au where lower(trim(coalesce(au.email, ''))) = clean_email
  ) then
    raise exception 'Este e-mail ja possui conta. Use um e-mail exclusivo para o administrador do novo clube';
  end if;

  update public.organization_admin_invitations
  set status = 'expired', updated_at = now()
  where email_normalized = clean_email
    and status = 'pending'
    and expires_at <= now();

  if exists (
    select 1 from public.organization_admin_invitations i
    where i.email_normalized = clean_email and i.status = 'pending'
  ) then
    raise exception 'Ja existe um convite ativo para este e-mail';
  end if;

  new_id := public.platform_create_organization_v1(
    p_name,
    p_slug,
    coalesce(nullif(trim(p_plan_code), ''), 'professional'),
    greatest(coalesce(p_max_users, 100), 1)
  );

  clean_branding := jsonb_build_object(
    'team_name', trim(p_name),
    'primary_color', case
      when coalesce(p_branding->>'primary_color', '') ~ '^#[0-9A-Fa-f]{6}$'
        then upper(p_branding->>'primary_color') else '#1E3A5F' end,
    'secondary_color', case
      when coalesce(p_branding->>'secondary_color', '') ~ '^#[0-9A-Fa-f]{6}$'
        then upper(p_branding->>'secondary_color') else '#D4AF37' end,
    'background_color', case
      when coalesce(p_branding->>'background_color', '') ~ '^#[0-9A-Fa-f]{6}$'
        then upper(p_branding->>'background_color') else '#F4F7FB' end,
    'surface_color', case
      when coalesce(p_branding->>'surface_color', '') ~ '^#[0-9A-Fa-f]{6}$'
        then upper(p_branding->>'surface_color') else '#FFFDF8' end,
    'text_color', case
      when coalesce(p_branding->>'text_color', '') ~ '^#[0-9A-Fa-f]{6}$'
        then upper(p_branding->>'text_color') else '#172338' end
  );

  update public.organizations
  set branding = clean_branding, updated_at = now()
  where id = new_id;

  insert into public.organization_settings (
    organization_id, key, value, updated_by, updated_at
  ) values (
    new_id, 'app_branding', clean_branding, auth.uid(), now()
  )
  on conflict (organization_id, key) do update
  set value = excluded.value,
      updated_by = excluded.updated_by,
      updated_at = now();

  update public.organization_features ofe
  set enabled = case
        when p_enabled_features is null then ofe.enabled
        else ofe.feature_key = any(selected_features)
      end,
      updated_by = auth.uid(),
      updated_at = now()
  where ofe.organization_id = new_id;

  insert into public.organization_admin_invitations (
    organization_id, email, email_normalized, role, status,
    expires_at, created_by
  ) values (
    new_id, clean_email, clean_email, 'admin', 'pending',
    now() + interval '30 days', auth.uid()
  ) returning id into invitation_id;

  return jsonb_build_object(
    'organization_id', new_id,
    'invitation_id', invitation_id,
    'admin_email', clean_email,
    'invitation_status', 'pending'
  );
end;
$$;

-- Mantem o comportamento atual para todos os cadastros normais. Quando o
-- e-mail possui convite ativo, o perfil ja nasce no clube correto como Admin.
create or replace function public.create_user_permissions()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  pending_invite public.organization_admin_invitations%rowtype;
  target_organization uuid := public.default_organization_id();
  has_invite boolean := false;
  target_type text := coalesce(
    nullif(new.raw_user_meta_data->>'user_type', ''), 'athlete'
  );
begin
  select i.*
  into pending_invite
  from public.organization_admin_invitations i
  where i.email_normalized = lower(trim(coalesce(new.email, '')))
    and i.status = 'pending'
    and i.expires_at > now()
  order by i.created_at desc
  limit 1
  for update;

  if found then
    has_invite := true;
    target_organization := pending_invite.organization_id;
    target_type := 'admin';
  end if;

  insert into public.profiles (
    id, email, user_type, full_name, organization_id, created_at, updated_at
  ) values (
    new.id,
    new.email,
    target_type,
    coalesce(
      nullif(new.raw_user_meta_data->>'full_name', ''),
      split_part(coalesce(new.email, 'usuario'), '@', 1)
    ),
    target_organization,
    now(),
    now()
  )
  on conflict (id) do update
  set organization_id = excluded.organization_id,
      user_type = case when has_invite then 'admin' else public.profiles.user_type end,
      updated_at = now();

  if pending_invite.id is not null then
    insert into public.user_roles (
      user_id, role, is_active, organization_id, updated_at
    ) values (
      new.id, 'admin', true, target_organization, now()
    );

    insert into public.organization_members (
      organization_id, user_id, role, status, is_default, joined_at, updated_at
    ) values (
      target_organization, new.id, 'admin', 'active', true, now(), now()
    )
    on conflict (organization_id, user_id) do update
    set role = 'admin', status = 'active', is_default = true, updated_at = now();

    update public.organization_admin_invitations
    set status = 'accepted', accepted_by = new.id,
        accepted_at = now(), updated_at = now()
    where id = pending_invite.id;
  end if;

  return new;
end;
$$;

revoke all on function public.platform_onboard_organization_v2(
  text, text, text, integer, text, text[], jsonb
) from public;
grant execute on function public.platform_onboard_organization_v2(
  text, text, text, integer, text, text[], jsonb
) to authenticated, service_role;

commit;
