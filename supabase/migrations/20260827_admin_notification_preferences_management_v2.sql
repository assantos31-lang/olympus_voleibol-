begin;

drop policy if exists admin_notification_preferences_select_self_v1
  on public.admin_notification_preferences;
drop policy if exists admin_notification_preferences_insert_self_v1
  on public.admin_notification_preferences;
drop policy if exists admin_notification_preferences_update_self_v1
  on public.admin_notification_preferences;

create policy admin_notification_preferences_select_org_admin_v2
on public.admin_notification_preferences for select to authenticated
using (
  public.is_organization_admin(organization_id)
  and exists (
    select 1
    from public.organization_members member
    where member.organization_id = admin_notification_preferences.organization_id
      and member.user_id = admin_notification_preferences.admin_id
      and member.status = 'active'
      and member.role in ('owner', 'admin')
  )
);

create policy admin_notification_preferences_insert_org_admin_v2
on public.admin_notification_preferences for insert to authenticated
with check (
  public.is_organization_admin(organization_id)
  and exists (
    select 1
    from public.organization_members member
    where member.organization_id = admin_notification_preferences.organization_id
      and member.user_id = admin_notification_preferences.admin_id
      and member.status = 'active'
      and member.role in ('owner', 'admin')
  )
);

create policy admin_notification_preferences_update_org_admin_v2
on public.admin_notification_preferences for update to authenticated
using (
  public.is_organization_admin(organization_id)
  and exists (
    select 1
    from public.organization_members member
    where member.organization_id = admin_notification_preferences.organization_id
      and member.user_id = admin_notification_preferences.admin_id
      and member.status = 'active'
      and member.role in ('owner', 'admin')
  )
)
with check (
  public.is_organization_admin(organization_id)
  and exists (
    select 1
    from public.organization_members member
    where member.organization_id = admin_notification_preferences.organization_id
      and member.user_id = admin_notification_preferences.admin_id
      and member.status = 'active'
      and member.role in ('owner', 'admin')
  )
);

commit;
