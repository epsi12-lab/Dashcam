import 'package:dashcam_core/dashcam_core.dart';
import 'package:test/test.dart';

const deviceA = '3f2a9c1e-7b4d-4e8a-9f10-2c6b8d4e5a71';
const deviceB = '9b1d4e7a-2c3f-4a5b-8c6d-7e8f9a0b1c2d';
const d = Duration(seconds: 10);
final t0 = DateTime.utc(2026, 11, 9, 8);

/// Hash fictif mais bien formé du segment n.
String h(int n) => n.toRadixString(16).padLeft(64, '0');

/// Empreinte telle qu'enregistrée en base pour le segment `seq`.
/// [delay] : délai réel entre la fin du segment et sa réception.
/// [clockOffset] : décalage de l'horloge du téléphone.
StoredFingerprint stored(
  String deviceId,
  int seq, {
  Duration delay = const Duration(seconds: 2),
  Duration clockOffset = Duration.zero,
  String? segmentHash,
}) {
  final realStart = t0.add(d * (seq - 41));
  return StoredFingerprint(
    deviceId: deviceId,
    seq: seq,
    segmentHash: segmentHash ?? h(seq),
    prevHash: seq == 1 ? null : h(seq - 1),
    startedAt: realStart.add(clockOffset),
    endedAt: realStart.add(d).add(clockOffset),
    receivedAt: realStart.add(d).add(delay),
    frozen: false,
  );
}

/// Fichier remis par le conducteur, avec son hash recalculé par le décodeur.
ProvidedSegment provided(String deviceId, int seq, {String? hash}) =>
    ProvidedSegment(
      fileName: SegmentName(deviceId: deviceId, seq: seq).fileName,
      computedHash: hash ?? h(seq),
    );

void main() {
  group('TU-07 : exemple des segments 41 à 45 (rapport, section 3.5)', () {
    final delays = {41: 13, 42: 12, 43: 14, 44: 12};
    final storedList = [
      for (var n = 41; n <= 45; n++)
        stored(deviceA, n,
            delay: n == 45 ? const Duration(minutes: 9) : Duration(seconds: delays[n]!)),
    ];
    final providedList = [
      provided(deviceA, 41),
      provided(deviceA, 42),
      provided(deviceA, 43, hash: 'e' * 64), // fichier retouché
      provided(deviceA, 44),
      provided(deviceA, 45),
    ];

    final results = verifySegments(provided: providedList, stored: storedList);

    test('les verdicts sont ceux du rapport, dans l\'ordre des fichiers', () {
      expect(results.map((r) => r.verdict), [
        Verdict.authentic,
        Verdict.authentic,
        Verdict.modified,
        Verdict.inconsistent,
        Verdict.authentic,
      ]);
    });

    test('le segment 45 porte l\'alerte d\'envoi tardif', () {
      expect(results[4].alerts, contains(Alert.lateDelivery));
    });

    test('les segments 41 à 44 ne portent aucune alerte', () {
      for (final r in results.take(4)) {
        expect(r.alerts, isEmpty, reason: r.fileName);
      }
    });

    test('chaque résultat contient une explication', () {
      for (final r in results) {
        expect(r.reason, isNotEmpty);
      }
    });
  });

  group('TU-05 : chaînage', () {
    test('une série complète et intacte est authentique, sans alerte', () {
      final results = verifySegments(
        provided: [for (var n = 41; n <= 43; n++) provided(deviceA, n)],
        stored: [for (var n = 41; n <= 43; n++) stored(deviceA, n)],
      );
      expect(results.map((r) => r.verdict), everyElement(Verdict.authentic));
      expect(results.map((r) => r.alerts), everyElement(isEmpty));
    });

    test('un trou dans la série déclenche l\'alerte sur le segment suivant', () {
      final results = verifySegments(
        provided: [provided(deviceA, 41), provided(deviceA, 42), provided(deviceA, 44)],
        stored: [for (var n = 41; n <= 44; n++) stored(deviceA, n)],
      );
      expect(results[2].verdict, Verdict.authentic);
      expect(results[2].alerts, contains(Alert.missingPrevious));
      expect(results[1].alerts, isEmpty);
    });

    test('une altération de la base est détectée par la chaîne stockée', () {
      // L'empreinte 43 a été modifiée en base : elle ne correspond plus
      // au prev_hash enregistré pour 44.
      final results = verifySegments(
        provided: [provided(deviceA, 44)],
        stored: [
          stored(deviceA, 43, segmentHash: 'd' * 64),
          stored(deviceA, 44),
        ],
      );
      expect(results.single.verdict, Verdict.inconsistent);
    });

    test('les chaînes de deux appareils ne se mélangent pas', () {
      final results = verifySegments(
        provided: [
          provided(deviceA, 41),
          provided(deviceB, 41),
          provided(deviceA, 42),
          provided(deviceB, 42),
        ],
        stored: [
          for (var n = 41; n <= 42; n++) ...[stored(deviceA, n), stored(deviceB, n)],
        ],
      );
      expect(results.map((r) => r.verdict), everyElement(Verdict.authentic));
      expect(results.map((r) => r.alerts), everyElement(isEmpty));
    });
  });

  group('TU-06 : contrôles temporels', () {
    test('un téléphone en avance de 5 minutes mais régulier ne déclenche rien', () {
      const offset = Duration(minutes: 5);
      final results = verifySegments(
        provided: [for (var n = 41; n <= 45; n++) provided(deviceA, n)],
        stored: [for (var n = 41; n <= 45; n++) stored(deviceA, n, clockOffset: offset)],
      );
      expect(results.map((r) => r.verdict), everyElement(Verdict.authentic));
      expect(results.map((r) => r.alerts), everyElement(isEmpty));
    });

    test('un segment qui commence avant la fin du précédent est incohérent', () {
      final s42 = stored(deviceA, 42);
      final overlapping = StoredFingerprint(
        deviceId: s42.deviceId,
        seq: s42.seq,
        segmentHash: s42.segmentHash,
        prevHash: s42.prevHash,
        startedAt: s42.startedAt.subtract(const Duration(seconds: 5)),
        endedAt: s42.endedAt,
        receivedAt: s42.receivedAt,
        frozen: false,
      );
      final results = verifySegments(
        provided: [provided(deviceA, 41), provided(deviceA, 42)],
        stored: [stored(deviceA, 41), overlapping],
      );
      expect(results[0].verdict, Verdict.authentic);
      expect(results[1].verdict, Verdict.inconsistent);
    });
  });

  group('Verdict « inconnu »', () {
    test('un nom de fichier invalide donne « inconnu »', () {
      final results = verifySegments(
        provided: [ProvidedSegment(fileName: 'video.mp4', computedHash: h(1))],
        stored: [stored(deviceA, 41)],
      );
      expect(results.single.verdict, Verdict.unknown);
    });

    test('un segment absent de la base donne « inconnu »', () {
      final results = verifySegments(
        provided: [provided(deviceA, 99)],
        stored: [stored(deviceA, 41)],
      );
      expect(results.single.verdict, Verdict.unknown);
    });
  });

  test('aucun fichier fourni donne une liste vide', () {
    expect(verifySegments(provided: [], stored: []), isEmpty);
  });
}