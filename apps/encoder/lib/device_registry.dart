import 'package:supabase_flutter/supabase_flutter.dart';

/// Enregistre le téléphone au nom du conducteur connecté.
///
/// Sans effet si le téléphone est déjà enregistré : la fonction peut donc
/// être appelée à chaque démarrage.
Future<void> registerDevice(SupabaseClient client, String deviceId) async {
  final ownerId = client.auth.currentUser?.id;
  if (ownerId == null) {
    throw StateError(
      'Aucun conducteur connecté : impossible d\'enregistrer le téléphone.',
    );
  }

  try {
    await client.from('devices').insert({'id': deviceId, 'owner_id': ownerId});
  } on PostgrestException catch (e) {
    // 23505 : le téléphone est déjà enregistré, aucune action n'est nécessaire.
    if (e.code != '23505') rethrow;
  }
}
