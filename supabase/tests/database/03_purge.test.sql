begin;
create extension if not exists pgtap with schema extensions;
select plan(3);

insert into public.insurers (id, name) values ('a0000000-0000-0000-0000-000000000000', 'Compagnie A');
insert into auth.users (id, email) values ('d1000000-0000-0000-0000-000000000000', 'conducteur1@a.fr');
insert into public.profiles (id, role, insurer_id)
  values ('d1000000-0000-0000-0000-000000000000', 'driver', 'a0000000-0000-0000-0000-000000000000');
insert into public.devices (id, owner_id)
  values ('e1000000-0000-0000-0000-000000000000', 'd1000000-0000-0000-0000-000000000000');

-- Segment 1 : expiré ; segment 2 : expiré mais gelé ; segment 3 : récent
insert into public.fingerprints (device_id, seq, segment_hash, prev_hash, started_at, ended_at, received_at, frozen) values
  ('e1000000-0000-0000-0000-000000000000', 1,
   '1111111111111111111111111111111111111111111111111111111111111111', null,
   now() - interval '40 days 20 seconds', now() - interval '40 days 10 seconds', now() - interval '40 days', false),
  ('e1000000-0000-0000-0000-000000000000', 2,
   '2222222222222222222222222222222222222222222222222222222222222222',
   '1111111111111111111111111111111111111111111111111111111111111111',
   now() - interval '40 days 10 seconds', now() - interval '40 days', now() - interval '40 days', true),
  ('e1000000-0000-0000-0000-000000000000', 3,
   '3333333333333333333333333333333333333333333333333333333333333333',
   '2222222222222222222222222222222222222222222222222222222222222222',
   now() - interval '10 seconds', now(), now(), false);

select is(private.purge_expired_fingerprints(interval '30 days'), 1,
  'TI-08 : une seule empreinte expirée et non gelée est purgée');

select is(array(select seq from public.fingerprints order by seq), array[2, 3],
  'TI-08 : les empreintes gelées et récentes sont conservées');

select is((select count(*)::int from cron.job where jobname = 'purge-expired-fingerprints'), 1,
  'EF-S02 : la purge quotidienne est planifiée');

select * from finish();
rollback;