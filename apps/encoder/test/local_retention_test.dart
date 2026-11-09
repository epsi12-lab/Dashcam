import 'package:dashcam_core/dashcam_core.dart';
import 'package:dashcam_encoder/local_retention.dart';
import 'package:dashcam_encoder/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const deviceId = '3f2a9c1e-7b4d-4e8a-9f10-2c6b8d4e5a71';
final t0 = DateTime.utc(2026, 11, 9, 8);
const d = Duration(seconds: 10);

String fileOf(int seq) => SegmentName(deviceId: deviceId, seq: seq).fileName;

/// Environnement de test : stockage en mémoire, horloge réglable,
/// et liste des fichiers « supprimés ».
class Env {
  Env._(this.store);

  final LocalStore store;
  final List<String> deleted = [];
  DateTime current = t0;
  Fingerprint? _last;

  static Future<Env> create() async => Env._(await LocalStore.open(
        await databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(singleInstance: false),
        ),
      ));

  LocalRetention retention() => LocalRetention(
        store: store,
        deleteFile: (name) async => deleted.add(name),
        now: () => current,
      );

  /// Enregistre les segments suivants : le n-ième couvre [t0 + (n-1)·D, t0 + n·D].
  Future<void> recordSegments(int count) async {
    for (var i = 0; i < count; i++) {
      final seq = (_last?.seq ?? 0) + 1;
      final start = t0.add(d * (seq - 1));
      final hash = seq.toRadixString(16).padLeft(64, '0');
      final last = _last;
      _last = last == null
          ? Fingerprint.first(
              deviceId: deviceId, segmentHash: hash, startedAt: start, endedAt: start.add(d))
          : last.next(segmentHash: hash, startedAt: start, endedAt: start.add(d));
      await store.recordSegment(_last!);
    }
  }
}

void main() {
  setUpAll(sqfliteFfiInit);

  group('TU-08 : purge locale', () {
    test('les segments de moins de 24 h sont conservés', () async {
      final env = await Env.create();
      await env.recordSegments(3);
      env.current = t0.add(const Duration(hours: 1));

      expect(await env.retention().run(), 0);
      expect(env.deleted, isEmpty);
    });

    test('les segments de plus de 24 h sont supprimés, fichier et ligne', () async {
      final env = await Env.create();
      await env.recordSegments(3);
      env.current = t0.add(const Duration(hours: 25));

      expect(await env.retention().run(), 3);
      expect(env.deleted, [fileOf(1), fileOf(2), fileOf(3)]);
      expect(await env.store.segmentFileNames(), isEmpty);
    });

    test('seuls les segments expirés sont supprimés', () async {
      final env = await Env.create();
      await env.recordSegments(2); // terminés à t0 + 10 s et t0 + 20 s
      env.current = t0.add(const Duration(hours: 24, seconds: 15));

      await env.retention().run();

      expect(env.deleted, [fileOf(1)]);
      expect(await env.store.segmentFileNames(), [fileOf(2)]);
    });

    test('la purge ne touche pas à la file d\'attente des empreintes', () async {
      final env = await Env.create();
      await env.recordSegments(3);
      env.current = t0.add(const Duration(hours: 25));

      await env.retention().run();

      expect(await env.store.pendingCount(), 3);
    });

    test('un second passage ne supprime rien de plus', () async {
      final env = await Env.create();
      await env.recordSegments(3);
      env.current = t0.add(const Duration(hours: 25));
      final retention = env.retention();

      await retention.run();
      expect(await retention.run(), 0);
      expect(env.deleted, hasLength(3));
    });
  });

  group('EF-E10 : protection d\'un incident', () {
    test('les segments de la minute précédant l\'incident sont protégés', () async {
      final env = await Env.create();
      await env.recordSegments(10); // couvrent t0 à t0 + 100 s

      // Incident à t0 + 70 s : fenêtre protégée [t0 + 10 s, t0 + 100 s].
      await env.retention().protectIncident(t0.add(const Duration(seconds: 70)));
      env.current = t0.add(const Duration(hours: 25));
      await env.retention().run();

      // Le segment 1 [t0, t0 + 10 s] touche la fenêtre sans la chevaucher.
      expect(env.deleted, [fileOf(1)]);
      expect(await env.store.segmentFileNames(), hasLength(9));
    });

    test('les segments enregistrés après l\'appui sont aussi protégés', () async {
      final env = await Env.create();

      // Appui à t0 + 5 s, avant tout enregistrement : fenêtre [t0 − 55 s, t0 + 35 s].
      await env.retention().protectIncident(t0.add(const Duration(seconds: 5)));
      await env.recordSegments(6); // couvrent t0 à t0 + 60 s
      env.current = t0.add(const Duration(hours: 25));
      await env.retention().run();

      // Les segments 1 à 4 chevauchent la fenêtre ; 5 [40 s, 50 s] et 6 [50 s, 60 s] non.
      expect(env.deleted, [fileOf(5), fileOf(6)]);
    });
  });
}