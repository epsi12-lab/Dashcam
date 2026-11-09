-- Compagnies d'assurance
create table public.insurers (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  created_at timestamptz not null default now()
);

-- Profil de chaque utilisateur (conducteur ou agent)
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  role text not null check (role in ('driver', 'agent')),
  insurer_id uuid not null references public.insurers (id),
  created_at timestamptz not null default now()
);

-- Téléphones enregistrés
create table public.devices (
  id uuid primary key,
  owner_id uuid not null references public.profiles (id),
  created_at timestamptz not null default now()
);

-- Empreintes des segments vidéo
create table public.fingerprints (
  id bigint generated always as identity primary key,
  device_id uuid not null references public.devices (id),
  seq integer not null check (seq >= 1),
  segment_hash text not null check (segment_hash ~ '^[0-9a-f]{64}$'),
  prev_hash text check (prev_hash ~ '^[0-9a-f]{64}$'),
  started_at timestamptz not null,
  ended_at timestamptz not null,
  received_at timestamptz not null default now(),
  frozen boolean not null default false,
  unique (device_id, seq),
  check (ended_at > started_at),
  check ((seq = 1) = (prev_hash is null))
);

create index fingerprints_received_at_idx on public.fingerprints (received_at);

-- Sécurité par défaut : tout est interdit tant qu'aucune règle n'autorise
alter table public.insurers enable row level security;
alter table public.profiles enable row level security;
alter table public.devices enable row level security;
alter table public.fingerprints enable row level security;