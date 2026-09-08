begin;

do $$
declare
  existing_job bigint;
begin
  select jobid into existing_job
  from cron.job
  where jobname = 'training-confirmation-deadline-every-minute'
  limit 1;

  if existing_job is not null then
    perform cron.unschedule(existing_job);
  end if;

  perform cron.schedule(
    'training-confirmation-deadline-every-minute',
    '* * * * *',
    $job$
      select net.http_post(
        url := 'https://wucxbbspybemvkqgqtou.supabase.co/functions/v1/send-training-confirmation-deadline-notifications',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'apikey', (
            select decrypted_secret
            from vault.decrypted_secrets
            where name = 'publishable_key'
          ),
          'Authorization', 'Bearer ' || (
            select decrypted_secret
            from vault.decrypted_secrets
            where name = 'publishable_key'
          ),
          'x-cron-secret', (
            select decrypted_secret
            from vault.decrypted_secrets
            where name = 'cleanup_cron_secret'
          )
        ),
        body := '{}'::jsonb
      );
    $job$
  );
end;
$$;

commit;
