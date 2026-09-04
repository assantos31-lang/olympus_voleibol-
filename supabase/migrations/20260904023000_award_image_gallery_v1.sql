-- Galeria de fotos das entregas de premiações, com capa e ordem configuráveis.

begin;

create table if not exists public.award_images (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  award_edition_id uuid not null,
  image_url text not null check (length(trim(image_url)) between 1 and 2048),
  sort_order integer not null default 0 check (sort_order >= 0),
  is_cover boolean not null default false,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  foreign key (award_edition_id, organization_id)
    references public.award_editions(id, organization_id) on delete cascade,
  unique (award_edition_id, image_url)
);

create index if not exists award_images_edition_order_idx
  on public.award_images (award_edition_id, sort_order);

create unique index if not exists award_images_one_cover_idx
  on public.award_images (award_edition_id)
  where is_cover;

alter table public.award_images enable row level security;

drop policy if exists award_images_select_v1 on public.award_images;
create policy award_images_select_v1 on public.award_images
for select to authenticated
using (
  public.can_access_tenant_v1(organization_id)
  and exists (
    select 1 from public.award_editions e
    where e.id = award_edition_id
      and e.organization_id = award_images.organization_id
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

drop policy if exists award_images_manage_v1 on public.award_images;
create policy award_images_manage_v1 on public.award_images
for all to authenticated
using (public.can_manage_awards_v1(organization_id))
with check (public.can_manage_awards_v1(organization_id));

grant select, insert, update, delete on public.award_images to authenticated;

alter table public.award_images replica identity full;

do $$
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) and not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'award_images'
  ) then
    alter publication supabase_realtime add table public.award_images;
  end if;
end;
$$;

-- Preserva as imagens antigas como capa da nova galeria.
insert into public.award_images (
  organization_id,
  award_edition_id,
  image_url,
  sort_order,
  is_cover,
  created_by
)
select
  e.organization_id,
  e.id,
  e.delivery_photo_url,
  0,
  true,
  e.created_by
from public.award_editions e
where coalesce(trim(e.delivery_photo_url), '') <> ''
on conflict (award_edition_id, image_url) do nothing;

commit;
