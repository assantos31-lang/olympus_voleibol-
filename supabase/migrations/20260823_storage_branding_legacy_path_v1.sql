-- Mantém compatibilidade com versões já publicadas que salvam a identidade
-- visual em branding/<organization_id>/..., sem abrir acesso entre clubes.

begin;

create or replace function public.storage_object_organization_v1(
  object_name text
)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  segment text;
begin
  if split_part(object_name, '/', 1) = 'organizations' then
    segment := split_part(object_name, '/', 2);
  elsif split_part(object_name, '/', 1) = 'branding' then
    segment := split_part(object_name, '/', 2);
  else
    return public.default_organization_id();
  end if;

  if segment ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    return segment::uuid;
  end if;

  return null;
end;
$$;

revoke all on function public.storage_object_organization_v1(text) from public;

commit;
