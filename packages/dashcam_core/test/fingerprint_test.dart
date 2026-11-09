import 'package:dashcam_core/dashcam_core.dart';
import 'package:test/test.dart';

void main() {
  const deviceId = '3f2a9c1e-7b4d-4e8a-9f10-2c6b8d4e5a71';
  final hashA = 'a' * 64;
  final hashB = 'b' * 64;
  final hashC = 'c' * 64;
  final t0 = DateTime.utc(2026, 11, 9, 8);
  const d = Duration(seconds: 10);

  Fingerprint firstSegment() => Fingerprint.first(
        deviceId: deviceId,
        segmentHash: hashA,
        startedAt: t0,
        endedAt: t0.add(d),
      );

  group('TU-04 : construction de la chaîne', () {
    test('le premier segment a le numéro 1 et pas de hash précédent', () {
      final f1 = firstSegment();
      expect(f1.seq, 1);
      expect(f1.prevHash, isNull);
    });

    test('next() incrémente le numéro et reprend le hash précédent', () {
      final f2 = firstSegment()
          .next(segmentHash: hashB, startedAt: t0.add(d), endedAt: t0.add(d * 2));
      expect(f2.deviceId, deviceId);
      expect(f2.seq, 2);
      expect(f2.prevHash, hashA);
    });

    test('une chaîne de trois segments est correctement reliée', () {
      final f1 = firstSegment();
      final f2 = f1.next(segmentHash: hashB, startedAt: t0.add(d), endedAt: t0.add(d * 2));
      final f3 = f2.next(segmentHash: hashC, startedAt: t0.add(d * 2), endedAt: t0.add(d * 3));
      expect([f1.seq, f2.seq, f3.seq], [1, 2, 3]);
      expect(f3.prevHash, f2.segmentHash);
      expect(f2.prevHash, f1.segmentHash);
    });
  });

  group('TU-04 : format envoyé à Supabase', () {
    test('seules les six colonnes autorisées par la base sont envoyées', () {
      expect(firstSegment().toInsertJson().keys.toSet(), {
        'device_id',
        'seq',
        'segment_hash',
        'prev_hash',
        'started_at',
        'ended_at',
      });
    });

    test('les heures sont envoyées en UTC, avec le suffixe Z', () {
      final local = DateTime(2026, 11, 9, 9); // heure locale du téléphone
      final json = Fingerprint.first(
        deviceId: deviceId,
        segmentHash: hashA,
        startedAt: local,
        endedAt: local.add(d),
      ).toInsertJson();

      final startedAt = json['started_at'] as String;
      expect(startedAt, endsWith('Z'));
      expect(DateTime.parse(startedAt).isAtSameMomentAs(local), isTrue);
    });

    test('une empreinte relue depuis son JSON est identique', () {
      final f2 = firstSegment()
          .next(segmentHash: hashB, startedAt: t0.add(d), endedAt: t0.add(d * 2));
      final json = f2.toInsertJson();
      expect(Fingerprint.fromInsertJson(json).toInsertJson(), json);
    });
  });

  group('TU-04 : mêmes règles que la base', () {
    test('un hash mal formé est refusé', () {
      expect(
        () => Fingerprint.first(
            deviceId: deviceId, segmentHash: 'abc', startedAt: t0, endedAt: t0.add(d)),
        throwsArgumentError,
      );
    });

    test('un identifiant d\'appareil invalide est refusé', () {
      expect(
        () => Fingerprint.first(
            deviceId: deviceId.toUpperCase(),
            segmentHash: hashA,
            startedAt: t0,
            endedAt: t0.add(d)),
        throwsArgumentError,
      );
    });

    test('une fin antérieure au début est refusée', () {
      expect(
        () => Fingerprint.first(
            deviceId: deviceId, segmentHash: hashA, startedAt: t0, endedAt: t0.subtract(d)),
        throwsArgumentError,
      );
    });

    test('un segment suivant sans hash précédent est refusé', () {
      expect(
        () => Fingerprint(
            deviceId: deviceId,
            seq: 2,
            segmentHash: hashB,
            prevHash: null,
            startedAt: t0,
            endedAt: t0.add(d)),
        throwsArgumentError,
      );
    });

    test('un premier segment avec un hash précédent est refusé', () {
      expect(
        () => Fingerprint(
            deviceId: deviceId,
            seq: 1,
            segmentHash: hashB,
            prevHash: hashA,
            startedAt: t0,
            endedAt: t0.add(d)),
        throwsArgumentError,
      );
    });
  });
}