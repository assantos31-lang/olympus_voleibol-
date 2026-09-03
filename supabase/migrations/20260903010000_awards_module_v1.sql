-- Premiacoes mensais e mural de entregas, isolados por clube.

begin;

create table if not exists public.award_definitions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  title text not null check (length(trim(title)) between 2 and 100),
  description text not null default '',
  source_type text not null default 'manual'
    check (source_type in ('checkin_ranking', 'training_highlight', 'monthly_evaluation', 'manual')),
  winner_count integer not null default 1 check (winner_count between 1 and 20),
  cover_image_url text,
  is_visible boolean not null default true,
  sort_order integer not null default 0,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, organization_id)
);

create table if not exists public.award_editions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  award_definition_id uuid not null,
  period_year integer not null check (period_year between 2020 and 2200),
  period_month integer not null check (period_month between 1 and 12),
  caption text not null default '',
  delivery_date date,
  delivery_photo_url text,
  is_published boolean not null default false,
  is_visible boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (award_definition_id, period_year, period_month),
  unique (id, organization_id),
  foreign key (award_definition_id, organization_id)
    references public.award_definitions(id, organization_id) on delete cascade
);

create table if not exists public.award_winners (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  award_edition_id uuid not null,
  profile_id uuid references public.profiles(id) on delete set null,
  winner_name text not null check (length(trim(winner_name)) between 1 and 160),
  winner_avatar_url text,
  position integer not null check (position between 1 and 20),
  result_label text not null default '',
  created_at timestamptz not null default now(),
  unique (award_edition_id, position),
  foreign key (award_edition_id, organization_id)
    references public.award_editions(id, organization_id) on delete cascade
);

create index if not exists award_definitions_org_visible_idx
  on public.award_definitions (organization_id, is_visible, sort_order, created_at);
create index if not exists award_editions_org_period_idx
  on public.award_editions (organization_id, period_year desc, period_month desc);
create index if not exists award_winners_edition_idx
  on public.award_winners (award_edition_id, position);

create or replace function public.can_manage_awards_v1(target_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
    and (
      public.is_platform_admin_v1()
      or public.is_organization_admin(target_organization_id)
      or (
        public.is_current_user_admin_v1()
        and public.is_organization_member(target_organization_id)
        and target_organization_id = public.current_organization_id()
      )
    )
$$;

revoke all on function public.can_manage_awards_v1(uuid) from public;
grant execute on function public.can_manage_awards_v1(uuid)
  to authenticated, service_role;

alter table public.award_definitions enable row level security;
alter table public.award_editions enable row level security;
alter table public.award_winners enable row level security;

drop policy if exists award_definitions_select_v1 on public.award_definitions;
create policy award_definitions_select_v1 on public.award_definitions
for select to authenticated
using (
  public.can_access_tenant_v1(organization_id)
  and (is_visible or public.can_manage_awards_v1(organization_id))
);
drop policy if exists award_definitions_manage_v1 on public.award_definitions;
create policy award_definitions_manage_v1 on public.award_definitions
for all to authenticated
using (public.can_manage_awards_v1(organization_id))
with check (public.can_manage_awards_v1(organization_id));

drop policy if exists award_editions_select_v1 on public.award_editions;
create policy award_editions_select_v1 on public.award_editions
for select to authenticated
using (
  public.can_access_tenant_v1(organization_id)
  and (
    (
      is_visible
      and is_published
      and exists (
        select 1 from public.award_definitions d
        where d.id = award_definition_id
          and d.organization_id = award_editions.organization_id
          and d.is_visible
      )
    )
    or public.can_manage_awards_v1(organization_id)
  )
);
drop policy if exists award_editions_manage_v1 on public.award_editions;
create policy award_editions_manage_v1 on public.award_editions
for all to authenticated
using (public.can_manage_awards_v1(organization_id))
with check (public.can_manage_awards_v1(organization_id));

drop policy if exists award_winners_select_v1 on public.award_winners;
create policy award_winners_select_v1 on public.award_winners
for select to authenticated
using (
  public.can_access_tenant_v1(organization_id)
  and exists (
    select 1 from public.award_editions e
    where e.id = award_edition_id
      and e.organization_id = award_winners.organization_id
      and (
        (
          e.is_visible
          and e.is_published
          and exists (
            select 1 from public.award_definitions d
            where d.id = e.award_definition_id
              and d.organization_id = e.organization_id
              and d.is_visible
          )
        )
        or public.can_manage_awards_v1(e.organization_id)
      )
  )
);
drop policy if exists award_winners_manage_v1 on public.award_winners;
create policy award_winners_manage_v1 on public.award_winners
for all to authenticated
using (public.can_manage_awards_v1(organization_id))
with check (
  public.can_manage_awards_v1(organization_id)
  and (
    profile_id is null
    or exists (
      select 1 from public.profiles p
      where p.id = profile_id
        and p.organization_id = award_winners.organization_id
    )
  )
);

grant select, insert, update, delete on public.award_definitions to authenticated;
grant select, insert, update, delete on public.award_editions to authenticated;
grant select, insert, update, delete on public.award_winners to authenticated;

commit;
