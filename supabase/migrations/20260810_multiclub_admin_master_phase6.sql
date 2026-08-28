-- Olympus / Plataforma de Clubes
-- Fase 6: Admin Master, planos e catalogo de funcionalidades por clube.
-- Idempotente. Nao altera nem remove dados dos modulos atuais.

begin;

create table if not exists public.platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  status text not null default 'active'
    check (status in ('active', 'suspended')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.platform_features (
  key text primary key,
  name text not null,
  description text not null default '',
  category text not null default 'geral',
  default_enabled boolean not null default true,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.organization_subscriptions (
  organization_id uuid primary key
    references public.organizations(id) on delete cascade,
  plan_code text not null default 'professional',
  status text not null default 'active'
    check (status in ('trial', 'active', 'past_due', 'suspended', 'cancelled')),
  max_users integer not null default 100 check (max_users > 0),
  max_storage_mb integer not null default 1024 check (max_storage_mb >= 0),
  starts_at timestamptz not null default now(),
  trial_ends_at timestamptz,
  current_period_ends_at timestamptz,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

create table if not exists public.organization_features (
  organization_id uuid not null
    references public.organizations(id) on delete cascade,
  feature_key text not null
    references public.platform_features(key) on delete cascade,
  enabled boolean not null default true,
  limits jsonb not null default '{}'::jsonb,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (organization_id, feature_key)
);

create index if not exists organization_features_enabled_idx
  on public.organization_features (organization_id, enabled);
create index if not exists organization_subscriptions_status_idx
  on public.organization_subscriptions (status, plan_code);

insert into public.platform_features
  (key, name, description, category, default_enabled, sort_order)
values
  ('agenda', 'Agenda e eventos', 'Eventos, convocacoes e presencas.', 'Esportivo', true, 10),
  ('checkin', 'Check-in', 'Confirmacao de presenca nos treinos.', 'Esportivo', true, 20),
  ('training_plans', 'Planejamento de treinos', 'Planos e programacoes dos treinadores.', 'Esportivo', true, 30),
  ('competitions', 'Competicoes', 'Jogos, amistosos e campeonatos.', 'Esportivo', true, 40),
  ('statistics', 'Estatisticas', 'Indicadores e evolucao dos atletas.', 'Desempenho', true, 50),
  ('evaluations', 'Avaliacoes', 'Avaliacoes de atletas e treinadores.', 'Desempenho', true, 60),
  ('chat', 'Chat', 'Conversas individuais, grupos e midias.', 'Comunicacao', true, 70),
  ('messages', 'Mensagens administrativas', 'Avisos, mural e comunicados.', 'Comunicacao', true, 80),
  ('birthdays', 'Aniversariantes', 'Listas e alertas de aniversarios.', 'Comunicacao', true, 90),
  ('financial', 'Financeiro', 'Mensalidades, pagamentos e recibos.', 'Gestao', true, 100),
  ('custom_branding', 'Identidade visual', 'Cores, escudo e fundos personalizados.', 'Gestao', true, 110),
  ('exports', 'Exportacoes', 'Relatorios e exportacao de dados.', 'Gestao', true, 120),
  ('advanced_media', 'Midias avancadas', 'Audio, video e arquivos no chat.', 'Complementos', true, 130),
  ('push_notifications', 'Notificacoes push', 'Alertas Android e iOS.', 'Complementos', true, 140)
on conflict (key) do update
set name = excluded.name,
    description = excluded.description,
    category = excluded.category,
    sort_order = excluded.sort_order,
    is_active = true,
    updated_at = now();

create or replace function public.is_platform_admin_v1()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.platform_admins pa
    where pa.user_id = auth.uid()
      and pa.status = 'active'
  )
$$;

-- A consulta previa confirmou uma unica conta com Olympus e Admin no e-mail.
-- A condicao not exists impede que uma reexecucao acrescente outro Master.
insert into public.platform_admins (user_id, status, created_by)
select au.id, 'active', au.id
from auth.users au
where lower(coalesce(au.email, '')) like '%olympus%'
  and lower(coalesce(au.email, '')) like '%admin%'
  and not exists (select 1 from public.platform_admins)
order by au.created_at
limit 1
on conflict (user_id) do update
set status = 'active', updated_at = now();

insert into public.organization_subscriptions (
  organization_id, plan_code, status, max_users, max_storage_mb
)
select id, 'enterprise', 'active', 10000, 10240
from public.organizations
where id = public.default_organization_id()
on conflict (organization_id) do nothing;

insert into public.organization_features (organization_id, feature_key, enabled)
select o.id, f.key, f.default_enabled
from public.organizations o
cross join public.platform_features f
on conflict (organization_id, feature_key) do nothing;

create or replace function public.platform_create_organization_v1(
  p_name text,
  p_slug text,
  p_plan_code text default 'professional',
  p_max_users integer default 100
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_id uuid;
  clean_name text := trim(coalesce(p_name, ''));
  clean_slug text := regexp_replace(lower(trim(coalesce(p_slug, ''))), '[^a-z0-9-]+', '-', 'g');
begin
  if not public.is_platform_admin_v1() then
    raise exception 'Acesso restrito ao Admin Master' using errcode = '42501';
  end if;
  if length(clean_name) < 2 then
    raise exception 'Informe o nome do clube';
  end if;
  clean_slug := trim(both '-' from clean_slug);
  if length(clean_slug) < 2 then
    raise exception 'Informe um identificador valido para o clube';
  end if;

  insert into public.organizations (
    slug, name, legal_name, status, is_active, branding, created_by
  )
  values (
    clean_slug,
    clean_name,
    clean_name,
    'active',
    true,
    jsonb_build_object(
      'team_name', clean_name,
      'primary_color', '#1E3A5F',
      'secondary_color', '#D4AF37',
      'background_color', '#F4F7FB',
      'surface_color', '#FFFDF8',
      'text_color', '#172338'
    ),
    auth.uid()
  )
  returning id into new_id;

  insert into public.organization_subscriptions (
    organization_id, plan_code, status, max_users, max_storage_mb, updated_by
  ) values (
    new_id,
    coalesce(nullif(trim(p_plan_code), ''), 'professional'),
    'active',
    greatest(coalesce(p_max_users, 100), 1),
    1024,
    auth.uid()
  );

  insert into public.organization_features (
    organization_id, feature_key, enabled, updated_by
  )
  select new_id, f.key, f.default_enabled, auth.uid()
  from public.platform_features f
  where f.is_active;

  return new_id;
end;
$$;

create or replace function public.platform_set_feature_v1(
  p_organization_id uuid,
  p_feature_key text,
  p_enabled boolean,
  p_limits jsonb default '{}'::jsonb
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
  if not exists (
    select 1 from public.platform_features f
    where f.key = p_feature_key and f.is_active
  ) then
    raise exception 'Funcionalidade invalida';
  end if;

  insert into public.organization_features (
    organization_id, feature_key, enabled, limits, updated_by, updated_at
  ) values (
    p_organization_id, p_feature_key, p_enabled,
    coalesce(p_limits, '{}'::jsonb), auth.uid(), now()
  )
  on conflict (organization_id, feature_key) do update
  set enabled = excluded.enabled,
      limits = excluded.limits,
      updated_by = excluded.updated_by,
      updated_at = now();
end;
$$;

create or replace function public.platform_update_organization_v1(
  p_organization_id uuid,
  p_organization_status text,
  p_subscription_status text,
  p_plan_code text,
  p_max_users integer
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
  if p_organization_status not in ('active', 'suspended', 'archived') then
    raise exception 'Status do clube invalido';
  end if;
  if p_subscription_status not in ('trial', 'active', 'past_due', 'suspended', 'cancelled') then
    raise exception 'Status da assinatura invalido';
  end if;

  update public.organizations
  set status = p_organization_status,
      is_active = p_organization_status = 'active',
      updated_at = now()
  where id = p_organization_id;

  insert into public.organization_subscriptions (
    organization_id, plan_code, status, max_users, updated_by, updated_at
  ) values (
    p_organization_id,
    coalesce(nullif(trim(p_plan_code), ''), 'professional'),
    p_subscription_status,
    greatest(coalesce(p_max_users, 100), 1),
    auth.uid(),
    now()
  )
  on conflict (organization_id) do update
  set plan_code = excluded.plan_code,
      status = excluded.status,
      max_users = excluded.max_users,
      updated_by = excluded.updated_by,
      updated_at = now();
end;
$$;

revoke all on function public.is_platform_admin_v1() from public;
revoke all on function public.platform_create_organization_v1(text, text, text, integer) from public;
revoke all on function public.platform_set_feature_v1(uuid, text, boolean, jsonb) from public;
revoke all on function public.platform_update_organization_v1(uuid, text, text, text, integer) from public;
grant execute on function public.is_platform_admin_v1() to authenticated, service_role;
grant execute on function public.platform_create_organization_v1(text, text, text, integer) to authenticated, service_role;
grant execute on function public.platform_set_feature_v1(uuid, text, boolean, jsonb) to authenticated, service_role;
grant execute on function public.platform_update_organization_v1(uuid, text, text, text, integer) to authenticated, service_role;

alter table public.platform_admins enable row level security;
alter table public.platform_features enable row level security;
alter table public.organization_subscriptions enable row level security;
alter table public.organization_features enable row level security;

drop policy if exists platform_admins_self_select_v1 on public.platform_admins;
create policy platform_admins_self_select_v1
on public.platform_admins for select to authenticated
using (user_id = auth.uid() and status = 'active');

drop policy if exists platform_features_authenticated_select_v1 on public.platform_features;
create policy platform_features_authenticated_select_v1
on public.platform_features for select to authenticated
using (is_active or public.is_platform_admin_v1());

drop policy if exists platform_features_master_all_v1 on public.platform_features;
create policy platform_features_master_all_v1
on public.platform_features for all to authenticated
using (public.is_platform_admin_v1())
with check (public.is_platform_admin_v1());

drop policy if exists organization_subscriptions_select_v1 on public.organization_subscriptions;
create policy organization_subscriptions_select_v1
on public.organization_subscriptions for select to authenticated
using (
  public.is_platform_admin_v1()
  or public.is_organization_member(organization_id)
);

drop policy if exists organization_subscriptions_master_all_v1 on public.organization_subscriptions;
create policy organization_subscriptions_master_all_v1
on public.organization_subscriptions for all to authenticated
using (public.is_platform_admin_v1())
with check (public.is_platform_admin_v1());

drop policy if exists organization_features_select_v1 on public.organization_features;
create policy organization_features_select_v1
on public.organization_features for select to authenticated
using (
  public.is_platform_admin_v1()
  or public.is_organization_member(organization_id)
);

drop policy if exists organization_features_master_all_v1 on public.organization_features;
create policy organization_features_master_all_v1
on public.organization_features for all to authenticated
using (public.is_platform_admin_v1())
with check (public.is_platform_admin_v1());

drop policy if exists organizations_platform_select_v1 on public.organizations;
create policy organizations_platform_select_v1
on public.organizations for select to authenticated
using (public.is_platform_admin_v1());

drop policy if exists organizations_platform_insert_v1 on public.organizations;
create policy organizations_platform_insert_v1
on public.organizations for insert to authenticated
with check (public.is_platform_admin_v1());

drop policy if exists organizations_platform_update_v1 on public.organizations;
create policy organizations_platform_update_v1
on public.organizations for update to authenticated
using (public.is_platform_admin_v1())
with check (public.is_platform_admin_v1());

drop policy if exists organization_members_platform_select_v1 on public.organization_members;
create policy organization_members_platform_select_v1
on public.organization_members for select to authenticated
using (public.is_platform_admin_v1());

grant select on public.platform_admins to authenticated;
grant select, insert, update on public.platform_features to authenticated;
grant select, insert, update on public.organization_subscriptions to authenticated;
grant select, insert, update on public.organization_features to authenticated;

do $$
declare
  table_name text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach table_name in array array['organization_features', 'organization_subscriptions']
    loop
      if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = table_name
      ) then
        execute format('alter publication supabase_realtime add table public.%I', table_name);
      end if;
    end loop;
  end if;
end;
$$;

commit;
