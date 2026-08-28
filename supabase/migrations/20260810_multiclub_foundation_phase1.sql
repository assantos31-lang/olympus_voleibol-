-- Olympus / Plataforma de Clubes
-- Fase 1: núcleo multi-clubes sem alterar o comportamento dos módulos atuais.
-- Esta migração é idempotente e associa todos os dados de usuário existentes
-- à organização Olympus. Chat, eventos e financeiro serão isolados nas fases
-- seguintes, depois da adaptação do aplicativo.

begin;

create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  slug text not null,
  name text not null,
  legal_name text,
  status text not null default 'active'
    check (status in ('active', 'suspended', 'archived')),
  is_active boolean not null default true,
  branding jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists organizations_slug_unique
  on public.organizations (lower(slug));

create table if not exists public.organization_members (
  organization_id uuid not null
    references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member'
    check (role in ('owner', 'admin', 'coach', 'athlete', 'member')),
  status text not null default 'active'
    check (status in ('invited', 'active', 'suspended', 'removed')),
  is_default boolean not null default false,
  joined_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (organization_id, user_id)
);

create index if not exists organization_members_user_idx
  on public.organization_members (user_id, status);

create unique index if not exists organization_members_one_default_idx
  on public.organization_members (user_id)
  where is_default and status = 'active';

create table if not exists public.organization_settings (
  organization_id uuid not null
    references public.organizations(id) on delete cascade,
  key text not null,
  value jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  primary key (organization_id, key)
);

insert into public.organizations (id, slug, name, legal_name, branding)
values (
  '00000000-0000-4000-8000-000000000001'::uuid,
  'olympus',
  'Olympus Voleibol',
  'Olympus Voleibol',
  jsonb_build_object(
    'team_name', 'Olympus Voleibol',
    'primary_color', '#1E3A5F',
    'secondary_color', '#D4AF37',
    'background_color', '#F4F7FB',
    'surface_color', '#FFFDF8'
  )
)
on conflict (id) do update
set name = excluded.name,
    legal_name = coalesce(public.organizations.legal_name, excluded.legal_name),
    updated_at = now();

create or replace function public.default_organization_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select o.id
  from public.organizations o
  where lower(o.slug) = 'olympus'
  limit 1
$$;

alter table public.profiles
  add column if not exists organization_id uuid
  references public.organizations(id) on delete restrict;

alter table public.user_profiles
  add column if not exists organization_id uuid
  references public.organizations(id) on delete restrict;

alter table public.user_roles
  add column if not exists organization_id uuid
  references public.organizations(id) on delete restrict;

alter table public.profiles
  alter column organization_id set default public.default_organization_id();
alter table public.user_profiles
  alter column organization_id set default public.default_organization_id();
alter table public.user_roles
  alter column organization_id set default public.default_organization_id();

update public.profiles
set organization_id = public.default_organization_id()
where organization_id is null;

update public.user_profiles
set organization_id = public.default_organization_id()
where organization_id is null;

update public.user_roles
set organization_id = public.default_organization_id()
where organization_id is null;

alter table public.profiles alter column organization_id set not null;
alter table public.user_profiles alter column organization_id set not null;
alter table public.user_roles alter column organization_id set not null;

create index if not exists profiles_organization_idx
  on public.profiles (organization_id, is_active);
create index if not exists user_profiles_organization_idx
  on public.user_profiles (organization_id);
create index if not exists user_roles_organization_idx
  on public.user_roles (organization_id, user_id, is_active);

insert into public.organization_members (
  organization_id,
  user_id,
  role,
  status,
  is_default
)
select
  p.organization_id,
  p.id,
  case
    when exists (
      select 1 from public.user_roles ur
      where ur.user_id = p.id and ur.is_active
        and lower(ur.role) in ('owner', 'master', 'super_admin')
    ) then 'owner'
    when exists (
      select 1 from public.user_roles ur
      where ur.user_id = p.id and ur.is_active
        and lower(ur.role) = 'admin'
    ) or lower(p.user_type) = 'admin' then 'admin'
    when exists (
      select 1 from public.user_roles ur
      where ur.user_id = p.id and ur.is_active
        and lower(ur.role) in ('coach', 'treinador')
    ) or lower(p.user_type) in ('coach', 'treinador') then 'coach'
    when exists (
      select 1 from public.user_roles ur
      where ur.user_id = p.id and ur.is_active
        and lower(ur.role) in ('athlete', 'atleta')
    ) or lower(p.user_type) in ('athlete', 'atleta') then 'athlete'
    else 'member'
  end,
  case when p.is_active then 'active' else 'suspended' end,
  true
from public.profiles p
join auth.users au on au.id = p.id
on conflict (organization_id, user_id) do update
set role = excluded.role,
    status = excluded.status,
    is_default = excluded.is_default,
    updated_at = now();

insert into public.organization_settings (organization_id, key, value)
select public.default_organization_id(), s.key, s.value
from public.app_settings s
where s.key = 'app_branding'
on conflict (organization_id, key) do update
set value = excluded.value,
    updated_at = now();

create or replace function public.is_organization_member(target_organization uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.organization_members om
    where om.organization_id = target_organization
      and om.user_id = auth.uid()
      and om.status = 'active'
  )
$$;

create or replace function public.is_organization_admin(target_organization uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.organization_members om
    where om.organization_id = target_organization
      and om.user_id = auth.uid()
      and om.status = 'active'
      and om.role in ('owner', 'admin')
  )
$$;

create or replace function public.current_organization_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select om.organization_id
  from public.organization_members om
  where om.user_id = auth.uid()
    and om.status = 'active'
  order by om.is_default desc, om.joined_at
  limit 1
$$;

revoke all on function public.default_organization_id() from public;
revoke all on function public.is_organization_member(uuid) from public;
revoke all on function public.is_organization_admin(uuid) from public;
revoke all on function public.current_organization_id() from public;
grant execute on function public.default_organization_id() to anon, authenticated, service_role;
grant execute on function public.is_organization_member(uuid) to authenticated, service_role;
grant execute on function public.is_organization_admin(uuid) to authenticated, service_role;
grant execute on function public.current_organization_id() to authenticated, service_role;

alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;
alter table public.organization_settings enable row level security;

drop policy if exists organizations_member_select_v1 on public.organizations;
create policy organizations_member_select_v1
on public.organizations for select to authenticated
using (public.is_organization_member(id));

drop policy if exists organizations_admin_update_v1 on public.organizations;
create policy organizations_admin_update_v1
on public.organizations for update to authenticated
using (public.is_organization_admin(id))
with check (public.is_organization_admin(id));

drop policy if exists organization_members_select_v1 on public.organization_members;
create policy organization_members_select_v1
on public.organization_members for select to authenticated
using (
  user_id = auth.uid()
  or public.is_organization_admin(organization_id)
);

drop policy if exists organization_members_admin_insert_v1 on public.organization_members;
create policy organization_members_admin_insert_v1
on public.organization_members for insert to authenticated
with check (public.is_organization_admin(organization_id));

drop policy if exists organization_members_admin_update_v1 on public.organization_members;
create policy organization_members_admin_update_v1
on public.organization_members for update to authenticated
using (public.is_organization_admin(organization_id))
with check (public.is_organization_admin(organization_id));

drop policy if exists organization_members_admin_delete_v1 on public.organization_members;
create policy organization_members_admin_delete_v1
on public.organization_members for delete to authenticated
using (public.is_organization_admin(organization_id));

drop policy if exists organization_settings_member_select_v1 on public.organization_settings;
create policy organization_settings_member_select_v1
on public.organization_settings for select to authenticated
using (public.is_organization_member(organization_id));

drop policy if exists organization_settings_admin_insert_v1 on public.organization_settings;
create policy organization_settings_admin_insert_v1
on public.organization_settings for insert to authenticated
with check (public.is_organization_admin(organization_id));

drop policy if exists organization_settings_admin_update_v1 on public.organization_settings;
create policy organization_settings_admin_update_v1
on public.organization_settings for update to authenticated
using (public.is_organization_admin(organization_id))
with check (public.is_organization_admin(organization_id));

drop policy if exists organization_settings_admin_delete_v1 on public.organization_settings;
create policy organization_settings_admin_delete_v1
on public.organization_settings for delete to authenticated
using (public.is_organization_admin(organization_id));

grant select on public.organizations to authenticated;
grant select, insert, update, delete on public.organization_members to authenticated;
grant select, insert, update, delete on public.organization_settings to authenticated;

commit;
