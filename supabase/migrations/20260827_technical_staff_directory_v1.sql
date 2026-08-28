begin;

create or replace function public.get_technical_staff_directory_v1()
returns table (
  id uuid,
  full_name text,
  email text,
  avatar_url text,
  user_type text,
  is_active boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  organization_id_value uuid := public.current_organization_id();
  user_is_admin boolean;
  user_is_coordinator boolean;
begin
  if organization_id_value is null or auth.uid() is null then
    return;
  end if;

  user_is_admin := public.is_organization_admin(organization_id_value);
  select exists (
    select 1
    from public.technical_staff_assignments tsa
    where tsa.organization_id = organization_id_value
      and tsa.user_id = auth.uid()
      and tsa.status = 'active'
      and tsa.technical_role = 'technical_coordinator'
      and tsa.can_manage_staff
  ) into user_is_coordinator;

  if not user_is_admin and not user_is_coordinator then
    return;
  end if;

  return query
  select
    p.id,
    p.full_name::text,
    p.email::text,
    p.avatar_url::text,
    p.user_type::text,
    p.is_active
  from public.profiles p
  where p.organization_id = organization_id_value
    and p.is_active = true
    and (
      (
        user_is_admin
        and (
          lower(trim(coalesce(p.user_type::text, ''))) in
            ('coach', 'treinador', 'tecnico', 'técnico')
          or exists (
            select 1
            from public.user_roles ur
            where ur.organization_id = organization_id_value
              and ur.user_id = p.id
              and ur.role = 'coach'
              and ur.is_active = true
          )
          or exists (
            select 1
            from public.technical_staff_assignments staff
            where staff.organization_id = organization_id_value
              and staff.user_id = p.id
              and staff.status = 'active'
          )
        )
      )
      or (
        user_is_coordinator
        and exists (
          select 1
          from public.technical_staff_assignments staff
          where staff.organization_id = organization_id_value
            and staff.user_id = p.id
            and staff.status = 'active'
        )
      )
    )
  order by p.full_name nulls last, p.email;
end;
$$;

revoke all on function public.get_technical_staff_directory_v1() from public;
grant execute on function public.get_technical_staff_directory_v1()
  to authenticated, service_role;

create or replace function public.coordinator_set_coach_training_authorization_v1(
  p_coach_id uuid,
  p_authorized boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  organization_id_value uuid;
begin
  select tsa.organization_id into organization_id_value
  from public.technical_staff_assignments tsa
  where tsa.user_id = auth.uid()
    and tsa.status = 'active'
    and tsa.technical_role = 'technical_coordinator'
    and tsa.can_manage_staff
  limit 1;

  if organization_id_value is null then
    raise exception 'Somente o coordenador pode alterar esta autorização.';
  end if;

  if not exists (
    select 1 from public.technical_staff_assignments target
    where target.organization_id = organization_id_value
      and target.user_id = p_coach_id
      and target.supervisor_user_id = auth.uid()
      and target.status = 'active'
      and target.technical_role <> 'technical_coordinator'
  ) then
    raise exception 'O profissional não está abaixo deste coordenador.';
  end if;

  update public.technical_staff_assignments
  set can_create_training = p_authorized,
      updated_at = now()
  where organization_id = organization_id_value
    and user_id = p_coach_id
    and supervisor_user_id = auth.uid();

  if not p_authorized then
    update public.training_planning_workflows
    set assigned_coach_id = auth.uid(),
        enabled_by = auth.uid(),
        enabled_at = coalesce(enabled_at, now()),
        status = 'enabled',
        updated_at = now()
    where organization_id = organization_id_value
      and assigned_coach_id = p_coach_id
      and status in ('pending', 'enabled');
  end if;
end;
$$;

revoke all on function public.coordinator_set_coach_training_authorization_v1(uuid, boolean)
  from public;
grant execute on function public.coordinator_set_coach_training_authorization_v1(uuid, boolean)
  to authenticated, service_role;

commit;
