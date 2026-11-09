-- Schéma privé, non exposé par l'API
create schema if not exists private;

-- Rôle de l'utilisateur connecté ('driver' ou 'agent')
create function private.my_role()
returns text
language sql stable security definer
set search_path = ''
as $$
  select role from public.profiles where id = (select auth.uid())
$$;

-- Compagnie de l'utilisateur connecté
create function private.my_insurer()
returns uuid
language sql stable security definer
set search_path = ''
as $$
  select insurer_id from public.profiles where id = (select auth.uid())
$$;

revoke all on function private.my_role(), private.my_insurer() from public;
grant usage on schema private to authenticated;
grant execute on function private.my_role(), private.my_insurer() to authenticated;

-- Par défaut, Supabase donne tous les droits sur les tables de public :
-- on repart de zéro
revoke all on public.insurers, public.profiles, public.devices, public.fingerprints
  from anon, authenticated;

-- Lecture : filtrée ensuite ligne par ligne par la RLS
grant select on public.insurers, public.profiles, public.devices, public.fingerprints
  to authenticated;

-- Enregistrement d'un téléphone
grant insert (id, owner_id) on public.devices to authenticated;

-- Envoi d'une empreinte : received_at, frozen et id ne sont PAS dans la liste
grant insert (device_id, seq, segment_hash, prev_hash, started_at, ended_at)
  on public.fingerprints to authenticated;

-- Gel : seule la colonne frozen peut être modifiée
grant update (frozen) on public.fingerprints to authenticated;

-- Compagnies : on ne voit que la sienne
create policy "lire sa compagnie" on public.insurers
  for select to authenticated
  using (id = (select private.my_insurer()));

-- Profils : le sien ; un agent voit aussi ceux de sa compagnie
create policy "lire les profils autorisés" on public.profiles
  for select to authenticated
  using (
    id = (select auth.uid())
    or ((select private.my_role()) = 'agent'
        and insurer_id = (select private.my_insurer()))
  );

-- Téléphones : les siens ; un agent voit ceux des conducteurs de sa compagnie
create policy "lire les téléphones autorisés" on public.devices
  for select to authenticated
  using (
    owner_id = (select auth.uid())
    or ((select private.my_role()) = 'agent'
        and exists (select 1 from public.profiles p
                    where p.id = devices.owner_id
                      and p.insurer_id = (select private.my_insurer())))
  );

-- Empreintes : celles de ses téléphones ; un agent voit celles de sa compagnie
create policy "lire les empreintes autorisées" on public.fingerprints
  for select to authenticated
  using (
    exists (select 1 from public.devices d where d.id = fingerprints.device_id)
  );

-- Un conducteur enregistre un téléphone à son nom
create policy "enregistrer son téléphone" on public.devices
  for insert to authenticated
  with check (
    owner_id = (select auth.uid())
    and (select private.my_role()) = 'driver'
  );

-- Un conducteur envoie des empreintes pour ses propres téléphones
create policy "envoyer ses empreintes" on public.fingerprints
  for insert to authenticated
  with check (
    (select private.my_role()) = 'driver'
    and exists (select 1 from public.devices d
                where d.id = fingerprints.device_id
                  and d.owner_id = (select auth.uid()))
  );

-- Un agent gèle les empreintes de sa compagnie (et ne peut pas dégeler)
create policy "geler les empreintes" on public.fingerprints
  for update to authenticated
  using ((select private.my_role()) = 'agent'
         and exists (select 1 from public.devices d where d.id = fingerprints.device_id))
  with check (frozen = true); 