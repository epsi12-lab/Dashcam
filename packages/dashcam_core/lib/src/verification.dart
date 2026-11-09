import 'segment_name.dart';
import 'stored_fingerprint.dart';

/// Verdict rendu pour un fichier fourni.
enum Verdict { authentic, modified, unknown, inconsistent }

/// Alertes qui s'ajoutent au verdict sans le changer.
enum Alert { lateDelivery, missingPrevious }

/// Fichier remis par le conducteur, avec le hash recalculé par le décodeur.
class ProvidedSegment {
  const ProvidedSegment({required this.fileName, required this.computedHash});

  final String fileName;
  final String computedHash;
}

/// Résultat de la vérification d'un fichier.
class SegmentResult {
  const SegmentResult({
    required this.fileName,
    required this.verdict,
    required this.reason,
    this.alerts = const {},
  });

  final String fileName;
  final Verdict verdict;
  final Set<Alert> alerts;

  /// Explication lisible du verdict, destinée à l'assureur.
  final String reason;
}

/// Vérifie les fichiers fournis par rapport aux empreintes enregistrées.
///
/// Fonction pure : aucun accès réseau ni fichier. Les résultats sont
/// renvoyés dans l'ordre des fichiers fournis.
List<SegmentResult> verifySegments({
  required List<ProvidedSegment> provided,
  required List<StoredFingerprint> stored,
  Duration segmentDuration = const Duration(seconds: 10),
  Duration tolerance = const Duration(seconds: 1),
}) {
  // 1. Empreintes enregistrées, rangées par appareil puis par numéro.
  final storedIndex = <String, Map<int, StoredFingerprint>>{};
  for (final s in stored) {
    (storedIndex[s.deviceId] ??= {})[s.seq] = s;
  }

  // 2. Délai médian de chaque appareil : son décalage habituel.
  final medianDelay = {
    for (final entry in storedIndex.entries)
      entry.key: _median(entry.value.values.map((s) => s.deliveryDelay)),
  };

  // 3. Fichiers fournis : noms lus une fois, hashs rangés par appareil.
  final names = [for (final p in provided) SegmentName.tryParse(p.fileName)];
  final providedHashes = <String, Map<int, String>>{};
  for (var i = 0; i < provided.length; i++) {
    final name = names[i];
    if (name != null) {
      (providedHashes[name.deviceId] ??= {})[name.seq] = provided[i].computedHash;
    }
  }

  // 4. Vérification de chaque fichier, dans l'ordre d'origine.
  return [
    for (var i = 0; i < provided.length; i++)
      _verifyOne(
        segment: provided[i],
        name: names[i],
        storedIndex: storedIndex,
        providedHashes: providedHashes,
        medianDelay: medianDelay,
        segmentDuration: segmentDuration,
        tolerance: tolerance,
      ),
  ];
}

SegmentResult _verifyOne({
  required ProvidedSegment segment,
  required SegmentName? name,
  required Map<String, Map<int, StoredFingerprint>> storedIndex,
  required Map<String, Map<int, String>> providedHashes,
  required Map<String, Duration> medianDelay,
  required Duration segmentDuration,
  required Duration tolerance,
}) {
  final fileName = segment.fileName;

  // Étape 1 : nom du fichier.
  if (name == null) {
    return SegmentResult(
      fileName: fileName,
      verdict: Verdict.unknown,
      reason: 'Nom de fichier non reconnu : forme attendue <appareil>_<numéro>.mp4.',
    );
  }

  // Étape 2 : empreinte de référence.
  final deviceStored = storedIndex[name.deviceId] ?? const <int, StoredFingerprint>{};
  final record = deviceStored[name.seq];
  if (record == null) {
    return SegmentResult(
      fileName: fileName,
      verdict: Verdict.unknown,
      reason: 'Aucune empreinte de référence pour ce segment (jamais reçue ou purgée).',
    );
  }

  // Alertes : elles ne changent pas le verdict.
  final alerts = <Alert>{};
  if (record.deliveryDelay > medianDelay[name.deviceId]! + segmentDuration * 2) {
    alerts.add(Alert.lateDelivery);
  }
  final deviceProvided = providedHashes[name.deviceId]!;
  final isFirstOfSeries = !deviceProvided.keys.any((seq) => seq < name.seq);
  if (!deviceProvided.containsKey(name.seq - 1) && !isFirstOfSeries) {
    alerts.add(Alert.missingPrevious);
  }

  // Étape 3 : comparaison des hashs.
  if (segment.computedHash != record.segmentHash) {
    return SegmentResult(
      fileName: fileName,
      verdict: Verdict.modified,
      alerts: alerts,
      reason: 'Le hash du fichier diffère de l\'empreinte enregistrée : le contenu a été modifié.',
    );
  }

  // Étape 4 : contrôles de cohérence.
  final problems = <String>[];
  final prevFileHash = deviceProvided[name.seq - 1];
  final prevStored = deviceStored[name.seq - 1];

  if (prevFileHash != null) {
    // Contrôle fort : le fichier précédent fourni doit être celui attendu.
    if (record.prevHash != prevFileHash) {
      problems.add('le fichier précédent ne correspond pas au hash précédent enregistré');
    }
  } else if (prevStored != null && record.prevHash != prevStored.segmentHash) {
    // Sans le fichier précédent : la chaîne stockée doit rester cohérente.
    problems.add('les empreintes enregistrées ne sont pas chaînées entre elles');
  }

  if (prevStored != null &&
      record.startedAt.isBefore(prevStored.endedAt.subtract(tolerance))) {
    problems.add('le segment commence avant la fin du précédent');
  }

  if (problems.isNotEmpty) {
    return SegmentResult(
      fileName: fileName,
      verdict: Verdict.inconsistent,
      alerts: alerts,
      reason: 'Contenu intact, mais ${problems.join(' ; ')}.',
    );
  }

  return SegmentResult(
    fileName: fileName,
    verdict: Verdict.authentic,
    alerts: alerts,
    reason: 'Le hash correspond à l\'empreinte enregistrée et la chaîne est cohérente.',
  );
}

/// Médiane d'une liste de durées non vide.
Duration _median(Iterable<Duration> values) {
  final sorted = values.toList()..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) ~/ 2;
}