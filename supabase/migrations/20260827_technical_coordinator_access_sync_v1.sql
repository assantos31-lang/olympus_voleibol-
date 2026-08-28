begin;

create or replace function public.normalize_technical_coordinator_access_v1()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.technical_role = 'technical_coordinator' then
    new.supervisor_user_id := null;
    new.can_create_training := true;
    new.can_publish_training := true;
    new.can_approve_training := true;
    new.can_manage_staff := true;
  end if;
  return new;
end;
$$;

drop trigger if exists technical_staff_coordinator_access_sync_v1
  on public.technical_staff_assignments;
create trigger technical_staff_coordinator_access_sync_v1
before insert or update on public.technical_staff_assignments
for each row execute function public.normalize_technical_coordinator_access_v1();

update public.technical_staff_assignments
set supervisor_user_id = null,
    can_create_training = true,
    can_publish_training = true,
    can_approve_training = true,
    can_manage_staff = true,
    updated_at = now()
where technical_role = 'technical_coordinator';

revoke all on function public.normalize_technical_coordinator_access_v1()
  from public;

commit;
