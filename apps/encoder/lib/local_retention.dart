import 'local_store.dart';

/// Purge locale des segments, par durée de conservation et par quota d'espace,
/// et protection des segments liés à un incident.
class LocalRetention {
  LocalRetention({
    required this.store,
    required this.deleteFile,
    required this.now,
    this.retention = const Duration(hours: 24),
    this.maxBytes,
    this.sizeOf,
    this.protectBefore = const Duration(seconds: 60),
    this.protectAfter = const Duration(seconds: 30),
  }) : assert(
         maxBytes == null || sizeOf != null,
         'Un quota d\'espace exige une fonction sizeOf',
       );

  final LocalStore store;

  /// Supprime un fichier vidéo à partir de son nom.
  final Future<void> Function(String fileName) deleteFile;

  /// Horloge, injectée pour pouvoir être maîtrisée dans les tests.
  final DateTime Function() now;

  /// Âge au-delà duquel un segment non protégé est supprimé.
  final Duration retention;

  /// Espace maximal occupé par les segments, en octets (`null` : aucun quota).
  final int? maxBytes;

  /// Taille d'un fichier vidéo, en octets.
  final Future<int> Function(String fileName)? sizeOf;

  /// Durée protégée avant le moment où un incident est signalé.
  final Duration protectBefore;
  /// Durée protégée après le moment où un incident est signalé.
  final Duration protectAfter;

  /// Supprime les segments expirés, puis ceux qui dépassent le quota.
  /// Les segments protégés ne sont jamais supprimés. Renvoie le nombre de
  /// segments supprimés.
  Future<int> run() async {
    var removed = 0;

    // 1. Durée de conservation.
    for (final segment in await store.expiredSegments(
      now().subtract(retention),
    )) {
      await _remove(segment.seq, segment.fileName);
      removed++;
    }

    // 2. Quota d'espace.
    final max = maxBytes;
    final size = sizeOf;
    if (max != null && size != null) {
      var total = 0;
      for (final name in await store.segmentFileNames()) {
        total += await size(name);
      }
      for (final segment in await store.unprotectedSegments()) {
        if (total <= max) break;
        final bytes = await size(segment.fileName);
        await _remove(segment.seq, segment.fileName);
        total -= bytes;
        removed++;
      }
    }

    return removed;
  }

  /// Protège les segments autour d'un incident, y compris ceux à venir.
  Future<void> protectIncident(DateTime at) => store.addProtectedWindow(
    at.subtract(protectBefore),
    at.add(protectAfter),
  );

  // Le fichier d'abord, la ligne ensuite : un arrêt brutal entre les deux ne
  // laisse jamais de fichier orphelin.
  Future<void> _remove(int seq, String fileName) async {
    await deleteFile(fileName);
    await store.removeSegment(seq);
  }
}
