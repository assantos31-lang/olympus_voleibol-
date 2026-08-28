-- Permite ao Admin Master localizar administradores de qualquer clube para
-- redefinir a senha pela funcao segura reset-user-password.

begin;

create or replace function public.platform_organization_admins_v1(
  p_organization_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  result jsonb;
begin
  if not public.is_platform_admin_v1() then
    raise exception 'Acesso restrito ao Admin Master' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.organizations o where o.id = p_organization_id
  ) then
    raise exception 'Clube nao encontrado';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'user_id', om.user_id,
        'role', om.role,
        'status', om.status,
        'full_name', coalesce(nullif(trim(p.full_name), ''), split_part(au.email, '@', 1)),
        'email', coalesce(nullif(trim(p.email), ''), au.email)
      )
      order by coalesce(nullif(trim(p.full_name), ''), au.email)
    ),
    '[]'::jsonb
  )
  into result
  from public.organization_members om
  left join public.profiles p on p.id = om.user_id
  left join auth.users au on au.id = om.user_id
  where om.organization_id = p_organization_id
    and om.status = 'active'
    and om.role in ('owner', 'admin');

  return result;
end;
$$;

revoke all on function public.platform_organization_admins_v1(uuid) from public;
grant execute on function public.platform_organization_admins_v1(uuid)
  to authenticated, service_role;

commit;
