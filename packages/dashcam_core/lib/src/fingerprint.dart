import 'patterns.dart';

/// Empreinte d'un segment vidéo, telle qu'envoyée par l'encodeur.
///
/// Les règles sont les mêmes que celles de la table `fingerprints` :
/// une erreur est détectée ici, avant tout envoi.
class Fingerprint {
  Fingerprint({
    required this.deviceId,
    required this.seq,
    required this.segmentHash,
    required this.prevHash,
    required this.startedAt,
    required this.endedAt,
  }) {
    if (!uuidPattern.hasMatch(deviceId)) {
      throw ArgumentError.value(deviceId, 'deviceId', 'uuid en minuscules attendu');
    }
    if (seq < 1) {
      throw ArgumentError.value(seq, 'seq', 'doit être supérieur ou égal à 1');
    }
    if (!sha256HexPattern.hasMatch(segmentHash)) {
      throw ArgumentError.value(segmentHash, 'segmentHash', 'SHA-256 hexadécimal minuscule attendu');
    }
    final prev = prevHash;
    if (prev != null && !sha256HexPattern.hasMatch(prev)) {
      throw ArgumentError.value(prev, 'prevHash', 'SHA-256 hexadécimal minuscule attendu');
    }
    if ((seq == 1) != (prev == null)) {
      throw ArgumentError('Seul le segment 1 est sans hash précédent (seq = $seq)');
    }
    if (!endedAt.isAfter(startedAt)) {
      throw ArgumentError('endedAt doit être postérieure à startedAt');
    }
  }

  /// Premier segment d'un appareil : numéro 1, sans hash précédent.
  factory Fingerprint.first({
    required String deviceId,
    required String segmentHash,
    required DateTime startedAt,
    required DateTime endedAt,
  }) =>
      Fingerprint(
        deviceId: deviceId,
        seq: 1,
        segmentHash: segmentHash,
        prevHash: null,
        startedAt: startedAt,
        endedAt: endedAt,
      );

  /// Relit une empreinte depuis le format d'envoi (file d'attente locale).
  factory Fingerprint.fromInsertJson(Map<String, Object?> json) => Fingerprint(
        deviceId: json['device_id'] as String,
        seq: json['seq'] as int,
        segmentHash: json['segment_hash'] as String,
        prevHash: json['prev_hash'] as String?,
        startedAt: DateTime.parse(json['started_at'] as String),
        endedAt: DateTime.parse(json['ended_at'] as String),
      );

  final String deviceId;
  final int seq;
  final String segmentHash;
  final String? prevHash;
  final DateTime startedAt;
  final DateTime endedAt;

  /// Segment suivant de la chaîne : numéro suivant, chaîné à celui-ci.
  Fingerprint next({
    required String segmentHash,
    required DateTime startedAt,
    required DateTime endedAt,
  }) =>
      Fingerprint(
        deviceId: deviceId,
        seq: seq + 1,
        segmentHash: segmentHash,
        prevHash: this.segmentHash,
        startedAt: startedAt,
        endedAt: endedAt,
      );

  /// Format d'envoi à Supabase : uniquement les six colonnes autorisées,
  /// heures en UTC.
  Map<String, Object?> toInsertJson() => {
        'device_id': deviceId,
        'seq': seq,
        'segment_hash': segmentHash,
        'prev_hash': prevHash,
        'started_at': startedAt.toUtc().toIso8601String(),
        'ended_at': endedAt.toUtc().toIso8601String(),
      };
}