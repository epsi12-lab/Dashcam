/// Empreinte telle qu'enregistrée en base, avec les valeurs fixées par le
/// serveur. C'est la référence à laquelle le décodeur compare les fichiers.
class StoredFingerprint {
  const StoredFingerprint({
    required this.deviceId,
    required this.seq,
    required this.segmentHash,
    required this.prevHash,
    required this.startedAt,
    required this.endedAt,
    required this.receivedAt,
    required this.frozen,
  });

  /// Construit l'objet à partir d'une ligne renvoyée par Supabase.
  factory StoredFingerprint.fromRow(Map<String, dynamic> row) => StoredFingerprint(
        deviceId: row['device_id'] as String,
        seq: row['seq'] as int,
        segmentHash: row['segment_hash'] as String,
        prevHash: row['prev_hash'] as String?,
        startedAt: DateTime.parse(row['started_at'] as String),
        endedAt: DateTime.parse(row['ended_at'] as String),
        receivedAt: DateTime.parse(row['received_at'] as String),
        frozen: row['frozen'] as bool,
      );

  final String deviceId;
  final int seq;
  final String segmentHash;
  final String? prevHash;
  final DateTime startedAt;
  final DateTime endedAt;
  final DateTime receivedAt;
  final bool frozen;

  /// Délai entre la fin du segment (horloge du téléphone) et sa réception
  /// (horloge du serveur). Inclut le décalage d'horloge du téléphone.
  Duration get deliveryDelay => receivedAt.difference(endedAt);
}