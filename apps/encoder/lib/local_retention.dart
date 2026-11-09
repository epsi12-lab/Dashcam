import 'local_store.dart';

/// Purge locale des segments expirés et protection des incidents.
class LocalRetention {
  LocalRetention({
    required this.store,
    required this.deleteFile,
    required this.now,
    this.retention = const Duration(hours: 24),
    this.protectBefore = const Duration(seconds: 60),
    this.protectAfter = const Duration(seconds: 30),
  });

  final LocalStore store;

  /// Supprime un fichier vidéo à partir de son nom.
  final Future<void> Function(String fileName) deleteFile;

  /// Horloge, injectée pour pouvoir être contrôlée dans les tests.
  final DateTime Function() now;

  final Duration retention;
  final Duration protectBefore;
  final Duration protectAfter;

  /// Supprime les segments expirés et non protégés. Renvoie leur nombre.
  Future<int> run() async {
    final expired = await store.expiredSegments(now().subtract(retention));
    for (final segment in expired) {
      // Fichier d'abord, ligne ensuite : un crash entre les deux ne laisse
      // jamais de fichier orphelin.
      await deleteFile(segment.fileName);
      await store.removeSegment(segment.seq);
    }
    return expired.length;
  }

  /// Protège les segments autour d'un incident, y compris ceux à venir.
  Future<void> protectIncident(DateTime at) =>
      store.addProtectedWindow(at.subtract(protectBefore), at.add(protectAfter));
}