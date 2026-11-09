begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

-- Données de départ : compagnies A et B, deux conducteurs et un agent chez A, un agent chez B
insert into public.insurers (id, name) values
  ('a0000000-0000-0000-0000-000000000000', 'Compagnie A'),
  ('b0000000-0000-0000-0000-000000000000', 'Compagnie B');
insert into auth.users (id, email) values
  ('d1000000-0000-0000-0000-000000000000', 'conducteur1@a.fr'),
  ('d2000000-0000-0000-0000-000000000000', 'conducteur2@a.fr'),
  ('aa000000-0000-0000-0000-000000000000', 'agent@a.fr'),
  ('ab000000-0000-0000-0000-000000000000', 'agent@b.fr');
insert into public.profiles (id, role, insurer_id) values
  ('d1000000-0000-0000-0000-000000000000', 'driver', 'a0000000-0000-0000-0000-000000000000'),
  ('d2000000-0000-0000-0000-000000000000', 'driver', 'a0000000-0000-0000-0000-000000000000'),
  ('aa000000-0000-0000-0000-000000000000', 'agent',  'a0000000-0000-0000-0000-000000000000'),
  ('ab000000-0000-0000-0000-000000000000', 'agent',  'b0000000-0000-0000-0000-000000000000');
insert into public.devices (id, owner_id) values
  ('e2000000-0000-0000-0000-000000000000', 'd2000000-0000-0000-0000-000000000000');

-- ===== Conducteur 1 =====
select set_config('request.jwt.claims', '{"sub":"d1000000-0000-0000-0000-000000000000","role":"authenticated"}', true);
set local role authenticated;

select lives_ok($$
  insert into public.devices (id, owner_id)
  values ('e1000000-0000-0000-0000-000000000000', 'd1000000-0000-0000-0000-000000000000')
$$, 'TI-02 : un conducteur enregistre son téléphone');

select throws_like($$
  insert into public.devices (id, owner_id)
  values ('e3000000-0000-0000-0000-000000000000', 'd2000000-0000-0000-0000-000000000000')
$$, '%row-level security%', 'TI-02 : un conducteur ne peut pas enregistrer un téléphone au nom d''un autre');

select lives_ok($$
  insert into public.fingerprints (device_id, seq, segment_hash, started_at, ended_at)
  values ('e1000000-0000-0000-0000-000000000000', 1,
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
          now() - interval '10 seconds', now())
$$, 'TI-02 : un conducteur envoie une empreinte pour son téléphone');

select throws_like($$
  insert into public.fingerprints (device_id, seq, segment_hash, started_at, ended_at)
  values ('e2000000-0000-0000-0000-000000000000', 1,
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
          now() - interval '10 seconds', now())
$$, '%row-level security%', 'TI-02 : un conducteur ne peut pas envoyer pour le téléphone d''un autre');

select throws_like($$
  insert into public.fingerprints (device_id, seq, segment_hash, prev_hash, started_at, ended_at, received_at)
  values ('e1000000-0000-0000-0000-000000000000', 2,
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
          now(), now() + interval '10 seconds', '2020-01-01')
$$, 'permission denied%', 'TI-04 : un client ne peut pas imposer received_at');

with u as (update public.fingerprints set frozen = true returning 1)
select is(count(*)::int, 0, 'TI-07 : un conducteur ne peut pas geler') from u;

select throws_like($$ delete from public.fingerprints $$,
  'permission denied%', 'TI-03 : un conducteur ne peut pas supprimer d''empreinte');

select throws_like($$ select private.purge_expired_fingerprints(interval '0 seconds') $$,
  'permission denied%', 'TI-08 : un utilisateur ne peut pas déclencher la purge');

select is((select count(*)::int from public.fingerprints), 1,
  'TI-06 : un conducteur voit ses empreintes');

-- ===== Conducteur 2 =====
reset role;
select set_config('request.jwt.claims', '{"sub":"d2000000-0000-0000-0000-000000000000","role":"authenticated"}', true);
set local role authenticated;

select is((select count(*)::int from public.fingerprints), 0,
  'TI-06 : un conducteur ne voit pas les empreintes d''un autre');

-- ===== Agent de la compagnie B =====
reset role;
select set_config('request.jwt.claims', '{"sub":"ab000000-0000-0000-0000-000000000000","role":"authenticated"}', true);
set local role authenticated;

select is((select count(*)::int from public.fingerprints), 0,
  'TI-06 : un agent ne voit pas les empreintes d''une autre compagnie');

with u as (update public.fingerprints set frozen = true returning 1)
select is(count(*)::int, 0, 'TI-07 : un agent ne peut pas geler pour une autre compagnie') from u;

-- ===== Agent de la compagnie A =====
reset role;
select set_config('request.jwt.claims', '{"sub":"aa000000-0000-0000-0000-000000000000","role":"authenticated"}', true);
set local role authenticated;

select is((select count(*)::int from public.fingerprints), 1,
  'TI-06 : un agent voit les empreintes de sa compagnie');

with u as (update public.fingerprints set frozen = true returning 1)
select is(count(*)::int, 1, 'TI-07 : un agent gèle une empreinte de sa compagnie') from u;

select throws_like($$ update public.fingerprints set frozen = false $$,
  '%row-level security%', 'TI-07 : un agent ne peut pas dégeler');

-- ===== Visiteur non connecté =====
reset role;
set local role anon;

select throws_like($$ select count(*) from public.fingerprints $$,
  'permission denied%', 'TI-01 : un visiteur non connecté n''a accès à rien');

reset role;
select * from finish();
rollback;