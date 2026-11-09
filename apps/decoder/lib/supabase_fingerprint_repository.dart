import 'package:dashcam_core/dashcam_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fingerprint_repository.dart';

/// Lit et gèle les empreintes dans Supabase. Les règles RLS limitent
/// automatiquement les résultats à la compagnie de l'agent connecté.
class SupabaseFingerprintRepository implements FingerprintRepository {
  SupabaseFingerprintRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<StoredFingerprint>> fetchRange({
    required String deviceId,
    required int fromSeq,
    required int toSeq,
  }) async {
    final rows = await _client
        .from('fingerprints')
        .select()
        .eq('device_id', deviceId)
        .gte('seq', fromSeq)
        .lte('seq', toSeq)
        .order('seq', ascending: true);
    return rows.map(StoredFingerprint.fromRow).toList();
  }

  @override
  Future<int> freeze({required String deviceId, required List<int> seqs}) async {
    final updated = await _client
        .from('fingerprints')
        .update({'frozen': true})
        .eq('device_id', deviceId)
        .inFilter('seq', seqs)
        .select('seq');
    return updated.length;
  }
}