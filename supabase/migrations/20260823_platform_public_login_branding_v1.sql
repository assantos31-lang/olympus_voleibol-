-- Identidade pública exibida antes da autenticação.
-- É independente da identidade interna do Olympus e dos demais clubes.

begin;

create table if not exists public.platform_public_settings (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);

insert into public.platform_public_settings (key, value)
values (
  'public_login_branding',
  jsonb_build_object(
    'team_name', 'Olympus Voleibol',
    'primary_color', '#1E3A5F',
    'secondary_color', '#D4AF37',
    'background_color', '#F4F7FB',
    'surface_color', '#FFFDF8',
    'text_color', '#172338',
    'logo_url', '',
    'background_image_url', '',
    'background_asset', 'assets/images/monte_olimpo_v2.png',
    'use_background_image', true,
    'background_overlay', 0.64,
    'card_radius', 18
  )
)
on conflict (key) do nothing;

alter table public.platform_public_settings enable row level security;

drop policy if exists platform_public_settings_read_v1
  on public.platform_public_settings;
create policy platform_public_settings_read_v1
on public.platform_public_settings
for select
to anon, authenticated
using (key = 'public_login_branding');

drop policy if exists platform_public_settings_master_write_v1
  on public.platform_public_settings;
create policy platform_public_settings_master_write_v1
on public.platform_public_settings
for all
to authenticated
using (public.is_platform_admin_v1())
with check (public.is_platform_admin_v1());

create or replace function public.get_public_login_branding_v1()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (
      select s.value
      from public.platform_public_settings s
      where s.key = 'public_login_branding'
    ),
    '{}'::jsonb
  )
$$;

create or replace function public.platform_set_public_login_branding_v1(
  p_branding jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized jsonb;
begin
  if not public.is_platform_admin_v1() then
    raise exception 'Acesso restrito ao Administrador Master.';
  end if;

  if p_branding is null or jsonb_typeof(p_branding) <> 'object' then
    raise exception 'Identidade visual inválida.';
  end if;

  normalized := jsonb_build_object(
    'team_name', coalesce(nullif(trim(p_branding->>'team_name'), ''), 'Olympus Voleibol'),
    'primary_color', coalesce(nullif(p_branding->>'primary_color', ''), '#1E3A5F'),
    'secondary_color', coalesce(nullif(p_branding->>'secondary_color', ''), '#D4AF37'),
    'background_color', coalesce(nullif(p_branding->>'background_color', ''), '#F4F7FB'),
    'surface_color', coalesce(nullif(p_branding->>'surface_color', ''), '#FFFDF8'),
    'text_color', coalesce(nullif(p_branding->>'text_color', ''), '#172338'),
    'logo_url', coalesce(p_branding->>'logo_url', ''),
    'background_image_url', coalesce(p_branding->>'background_image_url', ''),
    'background_asset', coalesce(nullif(p_branding->>'background_asset', ''), 'assets/images/monte_olimpo_v2.png'),
    'use_background_image', coalesce((p_branding->>'use_background_image')::boolean, true),
    'background_overlay', least(0.90, greatest(0.0, coalesce((p_branding->>'background_overlay')::numeric, 0.64))),
    'card_radius', least(32, greatest(8, coalesce((p_branding->>'card_radius')::numeric, 18)))
  );

  insert into public.platform_public_settings (
    key, value, updated_at, updated_by
  ) values (
    'public_login_branding', normalized, now(), auth.uid()
  )
  on conflict (key) do update
  set value = excluded.value,
      updated_at = excluded.updated_at,
      updated_by = excluded.updated_by;

  return normalized;
end;
$$;

revoke all on function public.get_public_login_branding_v1() from public;
revoke all on function public.platform_set_public_login_branding_v1(jsonb)
  from public;
grant execute on function public.get_public_login_branding_v1()
  to anon, authenticated, service_role;
grant execute on function public.platform_set_public_login_branding_v1(jsonb)
  to authenticated, service_role;

commit;
