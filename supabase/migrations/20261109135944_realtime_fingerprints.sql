-- Diffuse en temps réel les nouvelles empreintes aux clients abonnés.
-- La RLS s'applique : chaque agent ne reçoit que celles de sa compagnie.
alter publication supabase_realtime add table public.fingerprints;