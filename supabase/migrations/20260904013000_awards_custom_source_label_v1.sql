-- Permite ao administrador nomear tipos de prêmio definidos manualmente.

begin;

alter table public.award_definitions
  add column if not exists custom_source_label text not null default '';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'award_definitions_custom_source_label_length_v1'
      and conrelid = 'public.award_definitions'::regclass
  ) then
    alter table public.award_definitions
      add constraint award_definitions_custom_source_label_length_v1
      check (length(trim(custom_source_label)) <= 100);
  end if;
end;
$$;

commit;
