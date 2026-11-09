begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

-- Données de départ
insert into public.insurers (id, name) values ('a0000000-0000-0000-0000-000000000000', 'Compagnie A');
insert into auth.users (id, email) values
  ('d1000000-0000-0000-0000-000000000000', 'conducteur1@a.fr'),
  ('ff000000-0000-0000-0000-000000000000', 'inconnu@a.fr');
insert into public.profiles (id, role, insurer_id)
  values ('d1000000-0000-0000-0000-000000000000', 'driver', 'a0000000-0000-0000-0000-000000000000');
insert into public.devices (id, owner_id)
  values ('e1000000-0000-0000-0000-000000000000', 'd1000000-0000-0000-0000-000000000000');

select lives_ok($$
  insert into public.fingerprints (device_id, seq, segment_hash, started_at, ended_at)
  values ('e1000000-0000-0000-0000-000000000000', 1,
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
          now() - interval '10 seconds', now())
$$, 'Une empreinte valide est acceptée');

select throws_like($$
  insert into public.fingerprints (device_id, seq, segment_hash, prev_hash, started_at, ended_at)
  values ('e1000000-0000-0000-0000-000000000000', 2,
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b85',
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
          now(), now() + interval '10 seconds')
$$, '%fingerprints_segment_hash_format%', 'Un hash de 63 caractères est refusé');

select throws_like($$
  insert into public.fingerprints (device_id, seq, segment_hash, prev_hash, started_at, ended_at)
  values ('e1000000-0000-0000-0000-000000000000', 2,
          'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855',
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
          now(), now() + interval '10 seconds')
$$, '%fingerprints_segment_hash_format%', 'Un hash en majuscules est refusé');

select throws_like($$
  insert into public.fingerprints (device_id, seq, segment_hash, prev_hash, started_at, ended_at)
  values ('e1000000-0000-0000-0000-000000000000', 2,
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
          'pas-un-hash',
          now(), now() + interval '10 seconds')
$$, '%fingerprints_prev_hash_format%', 'Un prev_hash mal formé est refusé');

select throws_like($$
  insert into public.fingerprints (device_id, seq, segment_hash, started_at, ended_at)
  values ('e1000000-0000-0000-0000-000000000000', 2,
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
          now(), now() + interval '10 seconds')
$$, '%fingerprints_chain_start%', 'Un segment suivant sans prev_hash est refusé');

select throws_like($$
  insert into public.fingerprints (device_id, seq, segment_hash, prev_hash, started_at, ended_at)
  values ('e1000000-0000-0000-0000-000000000000', 1,
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
          now(), now() + interval '10 seconds')
$$, '%fingerprints_chain_start%', 'Un premier segment avec prev_hash est refusé');

select throws_like($$
  insert into public.fingerprints (device_id, seq, segment_hash, prev_hash, started_at, ended_at)
  values ('e1000000-0000-0000-0000-000000000000', 2,
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
          now(), now() - interval '10 seconds')
$$, '%fingerprints_time_order%', 'Une fin antérieure au début est refusée');

select throws_like($$
  insert into public.fingerprints (device_id, seq, segment_hash, started_at, ended_at)
  values ('e1000000-0000-0000-0000-000000000000', 1,
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
          now() - interval '10 seconds', now())
$$, '%fingerprints_device_seq_unique%', 'Un segment déjà enregistré est refusé');

select throws_like($$
  insert into public.profiles (id, role, insurer_id)
  values ('ff000000-0000-0000-0000-000000000000', 'admin', 'a0000000-0000-0000-0000-000000000000')
$$, '%profiles_role_valid%', 'Un rôle inconnu est refusé');

select * from finish();
rollback;