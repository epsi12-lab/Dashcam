-- Planificateur de tâches intégré à PostgreSQL
create extension if not exists pg_cron;

-- Supprime les empreintes non gelées reçues depuis plus longtemps que la rétention.
-- Renvoie le nombre d'empreintes supprimées.
create function private.purge_expired_fingerprints(retention interval)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  deleted integer;
begin
  delete from public.fingerprints
  where frozen = false
    and received_at < now() - retention;

  get diagnostics deleted = row_count;
  return deleted;
end;
$$;

-- Aucun utilisateur de l'API ne peut déclencher la purge
revoke all on function private.purge_expired_fingerprints(interval) from public;

-- Tous les jours à 03h17 (heure UTC), rétention de 30 jours
select cron.schedule(
  'purge-expired-fingerprints',
  '17 3 * * *',
  $$select private.purge_expired_fingerprints(interval '30 days')$$
);