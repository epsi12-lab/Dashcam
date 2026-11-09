import 'dart:math';

import 'package:dashcam_core/dashcam_core.dart';

import 'fingerprint_repository.dart';

/// Fichier choisi par l'agent : son nom et son contenu, lu en flux.
class PickedSegment {
  const PickedSegment({required this.fileName, required this.content});

  final String fileName;
  final Stream<List<int>> content;
}

/// Enchaîne le hachage des fichiers, la récupération des empreintes
/// et la vérification.
class VerificationService {
  VerificationService({
    required this.repository,
    this.margin = 100,
    this.segmentDuration = const Duration(seconds: 10),
  });

  final FingerprintRepository repository;

  /// Nombre de numéros récupérés de part et d'autre des fichiers fournis,
  /// pour calculer une médiane fiable des délais.
  final int margin;

  final Duration segmentDuration;

  Future<List<SegmentResult>> verify(
    List<PickedSegment> files, {
    void Function(int done, int total)? onProgress,
  }) async {
    // 1. Hachage, un fichier après l'autre.
    final provided = <ProvidedSegment>[];
    for (final file in files) {
      provided.add(ProvidedSegment(
        fileName: file.fileName,
        computedHash: await sha256OfStream(file.content),
      ));
      onProgress?.call(provided.length, files.length);
    }

    // 2. Plage de numéros fournie pour chaque appareil.
    final ranges = <String, ({int first, int last})>{};
    for (final segment in provided) {
      final name = SegmentName.tryParse(segment.fileName);
      if (name == null) continue;
      final range = ranges[name.deviceId];
      ranges[name.deviceId] = range == null
          ? (first: name.seq, last: name.seq)
          : (first: min(range.first, name.seq), last: max(range.last, name.seq));
    }

    // 3. Empreintes de référence, plage élargie de la marge.
    final stored = <StoredFingerprint>[];
    for (final MapEntry(key: deviceId, value: range) in ranges.entries) {
      stored.addAll(await repository.fetchRange(
        deviceId: deviceId,
        fromSeq: max(1, range.first - margin),
        toSeq: range.last + margin,
      ));
    }

    // 4. Vérification, par le module commun.
    return verifySegments(
      provided: provided,
      stored: stored,
      segmentDuration: segmentDuration,
    );
  }

  /// Gèle toutes les empreintes qui ont servi de référence, quel que soit
  /// le verdict. Renvoie le nombre d'empreintes gelées.
  Future<int> freeze(List<SegmentResult> results) async {
    final seqsByDevice = <String, List<int>>{};
    for (final result in results) {
      if (result.verdict == Verdict.unknown) continue;
      final name = SegmentName.tryParse(result.fileName);
      if (name == null) continue;
      (seqsByDevice[name.deviceId] ??= []).add(name.seq);
    }

    var total = 0;
    for (final MapEntry(key: deviceId, value: seqs) in seqsByDevice.entries) {
      total += await repository.freeze(deviceId: deviceId, seqs: seqs);
    }
    return total;
  }
}