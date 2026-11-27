import 'package:dashcam_core/dashcam_core.dart';
import 'package:dashcam_encoder/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const deviceId = '3f2a9c1e-7b4d-4e8a-9f10-2c6b8d4e5a71';
final t0 = DateTime.utc(2026, 11, 26, 8);
const d = Duration(seconds: 10);

String fileOf(int seq) => SegmentName(deviceId: deviceId, seq: seq).fileName;

/// Stockage en mémoire avec [count] segments : le n-ième couvre
/// [t0 + (n-1)·D, t0 + n·D].
Future<LocalStore> storeWith(int count) async {
  final store = await LocalStore.open(
    await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    ),
  );
  Fingerprint? fp;
  for (var seq = 1; seq <= count; seq++) {
    final start = t0.add(d * (seq - 1));
    final hash = seq.toRadixString(16).padLeft(64, '0');
    fp = fp == null
        ? Fingerprint.first(
            deviceId: deviceId,
            segmentHash: hash,
            startedAt: start,
            endedAt: start.add(d),
          )
        : fp.next(segmentHash: hash, startedAt: start, endedAt: start.add(d));
    await store.recordSegment(fp);
  }
  return store;
}

void main() {
  setUpAll(sqfliteFfiInit);

  group('EF-E08 : segments d\'un intervalle', () {
    test(
      'les segments qui chevauchent l\'intervalle sont renvoyés, dans l\'ordre',
      () async {
        final store = await storeWith(10);

        // [t0 + 25 s, t0 + 45 s] chevauche les segments 3, 4 et 5.
        final segments = await store.segmentsBetween(
          t0.add(const Duration(seconds: 25)),
          t0.add(const Duration(seconds: 45)),
        );

        expect(segments.map((s) => s.seq), [3, 4, 5]);
        expect(segments.map((s) => s.fileName), [
          fileOf(3),
          fileOf(4),
          fileOf(5),
        ]);
      },
    );

    test(
      'un segment qui touche seulement l\'intervalle n\'est pas renvoyé',
      () async {
        final store = await storeWith(10);

        // [t0 + 20 s, t0 + 40 s] : les segments 2 et 5 ne font que le toucher.
        final segments = await store.segmentsBetween(
          t0.add(const Duration(seconds: 20)),
          t0.add(const Duration(seconds: 40)),
        );

        expect(segments.map((s) => s.seq), [3, 4]);
      },
    );

    test('les 5 dernières minutes, à partir d\'une heure donnée', () async {
      final store = await storeWith(40); // de t0 à t0 + 400 s
      final now = t0.add(const Duration(seconds: 400));

      final segments = await store.segmentsBetween(
        now.subtract(const Duration(minutes: 5)),
        now,
      );

      // [t0 + 100 s, t0 + 400 s] : segments 11 à 40.
      expect(segments.first.seq, 11);
      expect(segments.last.seq, 40);
      expect(segments, hasLength(30));
    });

    test('un segment déjà purgé n\'est plus proposé', () async {
      final store = await storeWith(5);
      await store.removeSegment(2);

      final segments = await store.segmentsBetween(
        t0,
        t0.add(const Duration(seconds: 50)),
      );

      expect(segments.map((s) => s.seq), [1, 3, 4, 5]);
    });
  });

  group('EF-E08 : incidents protégés', () {
    test('aucun incident au départ', () async {
      final store = await storeWith(3);
      expect(await store.protectedWindows(), isEmpty);
    });

    test('les incidents sont listés du plus récent au plus ancien', () async {
      final store = await storeWith(3);
      final early = t0.add(const Duration(minutes: 1));
      final late = t0.add(const Duration(minutes: 30));

      await store.addProtectedWindow(
        early,
        early.add(const Duration(seconds: 90)),
      );
      await store.addProtectedWindow(
        late,
        late.add(const Duration(seconds: 90)),
      );

      final windows = await store.protectedWindows();
      expect(windows.map((w) => w.start), [late, early]);
      expect(windows.first.end, late.add(const Duration(seconds: 90)));
    });

    test('les heures relues sont en UTC', () async {
      final store = await storeWith(1);
      await store.addProtectedWindow(t0, t0.add(d));

      expect((await store.protectedWindows()).single.start.isUtc, isTrue);
    });
  });
}
