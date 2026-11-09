import 'dart:convert';

import 'package:dashcam_core/dashcam_core.dart';
import 'package:dashcam_encoder/local_store.dart';
import 'package:dashcam_encoder/segment_processor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const deviceId = '3f2a9c1e-7b4d-4e8a-9f10-2c6b8d4e5a71';
final t0 = DateTime.utc(2026, 11, 9, 8);
const d = Duration(seconds: 10);

Stream<List<int>> content(String text) => Stream.value(utf8.encode(text));

Future<LocalStore> memoryStore() async => LocalStore.open(
      await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      ),
    );

void main() {
  setUpAll(sqfliteFfiInit);

  test('le premier segment reçoit le numéro 1 et le hash de son contenu', () async {
    final processor =
        SegmentProcessor(store: await memoryStore(), deviceId: deviceId);

    final fp = await processor.process(
        content: content('segment 1'), startedAt: t0, endedAt: t0.add(d));

    expect(fp.seq, 1);
    expect(fp.prevHash, isNull);
    expect(fp.segmentHash, await sha256OfStream(content('segment 1')));
  });

  test('le segment suivant est chaîné au précédent', () async {
    final processor =
        SegmentProcessor(store: await memoryStore(), deviceId: deviceId);

    final fp1 = await processor.process(
        content: content('segment 1'), startedAt: t0, endedAt: t0.add(d));
    final fp2 = await processor.process(
        content: content('segment 2'), startedAt: t0.add(d), endedAt: t0.add(d * 2));

    expect(fp2.seq, 2);
    expect(fp2.prevHash, fp1.segmentHash);
  });

  test('chaque segment traité est mis en file d\'attente', () async {
    final store = await memoryStore();
    final processor = SegmentProcessor(store: store, deviceId: deviceId);

    await processor.process(
        content: content('segment 1'), startedAt: t0, endedAt: t0.add(d));
    await processor.process(
        content: content('segment 2'), startedAt: t0.add(d), endedAt: t0.add(d * 2));

    expect(await store.pendingCount(), 2);
  });

  test('après un redémarrage, la chaîne reprend là où elle s\'était arrêtée', () async {
    final store = await memoryStore();
    final before = SegmentProcessor(store: store, deviceId: deviceId);
    final fp1 = await before.process(
        content: content('segment 1'), startedAt: t0, endedAt: t0.add(d));

    // Nouvelle instance, même stockage : comme après un redémarrage.
    final after = SegmentProcessor(store: store, deviceId: deviceId);
    final fp2 = await after.process(
        content: content('segment 2'), startedAt: t0.add(d), endedAt: t0.add(d * 2));

    expect(fp2.seq, 2);
    expect(fp2.prevHash, fp1.segmentHash);
  });
}