import 'package:dashcam_core/dashcam_core.dart';

import 'local_store.dart';

/// Transforme un segment terminé en empreinte chaînée et la met en file.
///
/// Les appels doivent être faits l'un après l'autre (en attendant chaque
/// appel) : deux appels simultanés liraient le même dernier segment.
class SegmentProcessor {
  SegmentProcessor({required this.store, required this.deviceId});

  final LocalStore store;
  final String deviceId;

  /// Hache le contenu, puis enregistre l'empreinte.
  Future<Fingerprint> process({
    required Stream<List<int>> content,
    required DateTime startedAt,
    required DateTime endedAt,
  }) async =>
      record(
        segmentHash: await sha256OfStream(content),
        startedAt: startedAt,
        endedAt: endedAt,
      );

  /// Enregistre l'empreinte d'un segment dont le hash est déjà calculé.
  Future<Fingerprint> record({
    required String segmentHash,
    required DateTime startedAt,
    required DateTime endedAt,
  }) async {
    final last = await store.lastFingerprint();

    final fp = last == null
        ? Fingerprint.first(
            deviceId: deviceId,
            segmentHash: segmentHash,
            startedAt: startedAt,
            endedAt: endedAt,
          )
        : last.next(segmentHash: segmentHash, startedAt: startedAt, endedAt: endedAt);

    await store.recordSegment(fp);
    return fp;
  }
}