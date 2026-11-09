/// Motif d'un uuid en minuscules, comme ceux générés par l'application.
const _uuid = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';

final _uuidPattern = RegExp('^$_uuid\$');
final _fileNamePattern = RegExp('^($_uuid)_(\\d+)\\.mp4\$');

/// Nom de fichier d'un segment vidéo : `<appareil>_<séquence>.mp4`.
class SegmentName {
  SegmentName({required this.deviceId, required this.seq}) {
    if (!_uuidPattern.hasMatch(deviceId)) {
      throw ArgumentError.value(deviceId, 'deviceId', 'uuid en minuscules attendu');
    }
    if (seq < 1) {
      throw ArgumentError.value(seq, 'seq', 'doit être supérieur ou égal à 1');
    }
  }

  final String deviceId;
  final int seq;

  /// Nom du fichier, numéro complété à 6 chiffres pour un tri correct.
  String get fileName => '${deviceId}_${seq.toString().padLeft(6, '0')}.mp4';

  /// Relit un nom de fichier. Renvoie `null` si le nom n'est pas valide.
  static SegmentName? tryParse(String fileName) {
    final match = _fileNamePattern.firstMatch(fileName);
    if (match == null) return null;

    final seq = int.tryParse(match.group(2)!);
    if (seq == null || seq < 1) return null;

    return SegmentName(deviceId: match.group(1)!, seq: seq);
  }
}