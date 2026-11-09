import 'dart:io';

import 'package:dashcam_core/dashcam_core.dart';
import 'package:dashcam_encoder/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const deviceId = '3f2a9c1e-7b4d-4e8a-9f10-2c6b8d4e5a71';
final t0 = DateTime.utc(2026, 11, 9, 8);
const d = Duration(seconds: 10);

Fingerprint first() => Fingerprint.first(
      deviceId: deviceId,
      segmentHash: 'a' * 64,
      startedAt: t0,
      endedAt: t0.add(d),
    );

Fingerprint second() =>
    first().next(segmentHash: 'b' * 64, startedAt: t0.add(d), endedAt: t0.add(d * 2));

/// Base en mémoire, neuve pour chaque test.
Future<Database> memoryDb() => databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );

void main() {
  setUpAll(sqfliteFfiInit);

  test('une base neuve est vide', () async {
    final store = await LocalStore.open(await memoryDb());
    expect(await store.lastFingerprint(), isNull);
    expect(await store.pendingCount(), 0);
  });

  test('un segment enregistré met à jour la chaîne, la file et la liste des segments',
      () async {
    final store = await LocalStore.open(await memoryDb());
    await store.recordSegment(first());

    expect((await store.lastFingerprint())?.seq, 1);
    expect(await store.pendingCount(), 1);
    expect(await store.segmentFileNames(),
        [SegmentName(deviceId: deviceId, seq: 1).fileName]);
  });

  test('la file rend les empreintes dans l\'ordre des numéros', () async {
    final store = await LocalStore.open(await memoryDb());
    await store.recordSegment(first());
    await store.recordSegment(second());

    final pending = await store.pendingUploads();
    expect(pending.map((f) => f.seq), [1, 2]);
    expect(pending[1].prevHash, 'a' * 64);
  });

  test('une empreinte confirmée quitte la file, mais pas la chaîne ni les segments',
      () async {
    final store = await LocalStore.open(await memoryDb());
    await store.recordSegment(first());
    await store.markUploaded(1);

    expect(await store.pendingCount(), 0);
    expect((await store.lastFingerprint())?.seq, 1);
    expect(await store.segmentFileNames(), hasLength(1));
  });

  test('TI-11 : un échec en cours d\'enregistrement ne laisse aucune trace partielle',
      () async {
    final db = await memoryDb();
    final store = await LocalStore.open(db);
    await store.recordSegment(first());

    // On provoque un conflit : une ligne occupe déjà le numéro 2 dans `segments`.
    await db.insert('segments',
        {'seq': 2, 'file_name': 'x', 'started_at': '', 'ended_at': ''});

    await expectLater(store.recordSegment(second()), throwsA(anything));

    // La transaction a été annulée en entier.
    expect((await store.lastFingerprint())?.seq, 1);
    expect(await store.pendingCount(), 1);
  });

  test('TI-11 : la chaîne et la file survivent à la fermeture de l\'application',
      () async {
    final dir = await Directory.systemTemp.createTemp('dashcam_test');
    final path = '${dir.path}/encoder.db';

    final db1 = await databaseFactoryFfi.openDatabase(path);
    await (await LocalStore.open(db1)).recordSegment(first());
    await db1.close();

    final db2 = await databaseFactoryFfi.openDatabase(path);
    final reopened = await LocalStore.open(db2);
    expect((await reopened.lastFingerprint())?.segmentHash, 'a' * 64);
    expect(await reopened.pendingCount(), 1);

    await db2.close();
    await dir.delete(recursive: true);
  });
}