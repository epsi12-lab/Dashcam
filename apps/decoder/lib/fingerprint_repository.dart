import 'package:dashcam_core/dashcam_core.dart';

/// Accès aux empreintes enregistrées. L'implémentation réelle interroge
/// Supabase ; les tests utilisent une implémentation simulée.
abstract interface class FingerprintRepository {
  /// Empreintes d'un appareil dont le numéro est compris entre
  /// [fromSeq] et [toSeq], bornes incluses.
  Future<List<StoredFingerprint>> fetchRange({
    required String deviceId,
    required int fromSeq,
    required int toSeq,
  });

  /// Gèle les empreintes indiquées. Renvoie le nombre d'empreintes
  /// effectivement gelées.
  Future<int> freeze({required String deviceId, required List<int> seqs});
}
