import 'package:supabase_flutter/supabase_flutter.dart';

/// Enregistre le téléphone au nom du conducteur connecté.
///
/// Sans effet si le téléphone est déjà enregistré : l'application peut
/// l'appeler à chaque démarrage.
Future<void> registerDevice(SupabaseClient client, String deviceId) async {
  final ownerId = client.auth.currentUser?.id;
  if (ownerId == null) {
    throw StateError('Aucun conducteur connecté : impossible d\'enregistrer le téléphone.');
  }

  try {
    await client.from('devices').insert({'id': deviceId, 'owner_id': ownerId});
  } on PostgrestException catch (e) {
    // 23505 : le téléphone est déjà enregistré, il n'y a rien à faire.
    if (e.code != '23505') rethrow;
  }
}