import 'package:dashcam_core/dashcam_core.dart';

import 'local_store.dart';

/// Transforme un segment terminé en empreinte chaînée et la met en file.
///
/// Les appels doivent être faits l'un après l'autre (en attendant chaque
/// `process`) : deux appels simultanés liraient le même dernier segment.
class SegmentProcessor {
  SegmentProcessor({required this.store, required this.deviceId});

  final LocalStore store;
  final String deviceId;

  Future<Fingerprint> process({
    required Stream<List<int>> content,
    required DateTime startedAt,
    required DateTime endedAt,
  }) async {
    final hash = await sha256OfStream(content);
    final last = await store.lastFingerprint();

    final fp = last == null
        ? Fingerprint.first(
            deviceId: deviceId,
            segmentHash: hash,
            startedAt: startedAt,
            endedAt: endedAt,
          )
        : last.next(segmentHash: hash, startedAt: startedAt, endedAt: endedAt);

    await store.recordSegment(fp);
    return fp;
  }
}