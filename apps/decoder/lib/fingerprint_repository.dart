import 'package:dashcam_core/dashcam_core.dart';

/// Accès aux empreintes enregistrées. La vraie implémentation interroge
/// Supabase ; les tests utilisent une imitation.
abstract interface class FingerprintRepository {
  /// Empreintes d'un appareil dont le numéro est compris entre
  /// [fromSeq] et [toSeq], bornes incluses.
  Future<List<StoredFingerprint>> fetchRange({
    required String deviceId,
    required int fromSeq,
    required int toSeq,
  });

  /// Gèle les empreintes indiquées. Renvoie le nombre réellement gelé.
  Future<int> freeze({required String deviceId, required List<int> seqs});
}