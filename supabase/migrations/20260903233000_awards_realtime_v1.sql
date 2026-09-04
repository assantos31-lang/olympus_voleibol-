-- Atualiza o mural de premiações imediatamente após mudanças no banco.

begin;

alter table public.award_definitions replica identity full;
alter table public.award_editions replica identity full;
alter table public.award_winners replica identity full;

do $$
declare
  table_name text;
begin
  if exists (
    select 1 from pg_publication where pubname = 'supabase_realtime'
  ) then
    foreach table_name in array array[
      'award_definitions',
      'award_editions',
      'award_winners'
    ]
    loop
      if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = table_name
      ) then
        execute format(
          'alter publication supabase_realtime add table public.%I',
          table_name
        );
      end if;
    end loop;
  end if;
end;
$$;

commit;
