-- Données de démonstration : développement local uniquement.
-- Rejouées par `supabase db reset`, jamais envoyées à la base du cloud.
-- Les identifiants commencent par 5eed pour ne jamais entrer en conflit
-- avec ceux des tests pgTAP.

insert into public.insurers (id, name) values
  ('5eed0000-0000-0000-0000-00000000000a', 'Assur Alpha'),
  ('5eed0000-0000-0000-0000-00000000000b', 'Assur Beta');

do $$
declare
  u record;
begin
  for u in
    select * from (values
      ('5eed0000-0000-0000-0000-000000000001'::uuid, 'conducteur1@alpha.test', 'driver',
       '5eed0000-0000-0000-0000-00000000000a'::uuid),
      ('5eed0000-0000-0000-0000-000000000002'::uuid, 'conducteur2@alpha.test', 'driver',
       '5eed0000-0000-0000-0000-00000000000a'::uuid),
      ('5eed0000-0000-0000-0000-000000000003'::uuid, 'agent@alpha.test', 'agent',
       '5eed0000-0000-0000-0000-00000000000a'::uuid),
      ('5eed0000-0000-0000-0000-000000000004'::uuid, 'agent@beta.test', 'agent',
       '5eed0000-0000-0000-0000-00000000000b'::uuid)
    ) as t(id, email, role, insurer_id)
  loop
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at,
      confirmation_token, recovery_token, email_change_token_new, email_change
    ) values (
      '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated',
      u.email, extensions.crypt('dashcam-demo', extensions.gen_salt('bf')),
      now(), '{"provider":"email","providers":["email"]}', '{}',
      now(), now(),
      '', '', '', ''
    );

    insert into auth.identities (
      id, user_id, provider_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at
    ) values (
      gen_random_uuid(), u.id, u.id::text,
      jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
      'email', now(), now(), now()
    );

    insert into public.profiles (id, role, insurer_id)
    values (u.id, u.role, u.insurer_id);
  end loop;
end $$;