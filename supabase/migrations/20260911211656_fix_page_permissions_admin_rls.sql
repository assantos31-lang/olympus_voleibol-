begin;

-- The legacy policies only recognized profiles.user_type = 'admin'. That
-- excludes organization owners/admins (including Admin Master) and prevents
-- them from creating a first permission row for a coach.
drop policy if exists admins_manage_permissions on public.page_permissions;
create policy admins_manage_permissions
on public.page_permissions
as permissive
for all
to authenticated
using (
  (select public.is_platform_admin_v1())
  or (select public.is_organization_admin(organization_id))
)
with check (
  (select public.is_platform_admin_v1())
  or (select public.is_organization_admin(organization_id))
);

drop policy if exists admins_select_all_permissions on public.page_permissions;
create policy admins_select_all_permissions
on public.page_permissions
as permissive
for select
to authenticated
using (
  (select public.is_platform_admin_v1())
  or (select public.is_organization_admin(organization_id))
);

commit;
