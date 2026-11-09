@Tags(['integration'])
library;

import 'package:dashcam_core/dashcam_core.dart';
import 'package:dashcam_encoder/device_registry.dart';
import 'package:dashcam_encoder/fingerprint_sender.dart';
import 'package:dashcam_encoder/local_store.dart';
import 'package:dashcam_encoder/supabase_fingerprint_sender.dart';
import 'package:dashcam_encoder/uploader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

// Supabase local et comptes de démonstration (supabase/seed.sql).
const url = 'http://127.0.0.1:54321';
const publishableKey = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';
const password = 'dashcam-demo';

Future<SupabaseClient> signedIn(String email) async {
  final client = SupabaseClient(url, publishableKey);
  await client.auth.signInWithPassword(email: email, password: password);
  return client;
}

/// Premier segment d'un téléphone, terminé à l'instant.
Fingerprint firstOf(String deviceId) {
  final end = DateTime.now().toUtc();
  return Fingerprint.first(
    deviceId: deviceId,
    segmentHash: 'a' * 64,
    startedAt: end.subtract(const Duration(seconds: 10)),
    endedAt: end,
  );
}

void main() {
  late SupabaseClient driver1;
  late SupabaseClient driver2;

  setUpAll(() async {
    sqfliteFfiInit();
    driver1 = await signedIn('conducteur1@alpha.test');
    driver2 = await signedIn('conducteur2@alpha.test');
  });

  tearDownAll(() async {
    await driver1.dispose();
    await driver2.dispose();
  });

  test('TI-09 : un téléphone s\'enregistre, et un second enregistrement est sans effet',
      () async {
    final deviceId = const Uuid().v4();

    await registerDevice(driver1, deviceId);
    await registerDevice(driver1, deviceId); // comme à chaque démarrage

    final rows = await driver1.from('devices').select().eq('id', deviceId);
    expect(rows, hasLength(1));
  });

  test('TI-09 : une empreinte envoyée est enregistrée, avec l\'heure du serveur',
      () async {
    final deviceId = const Uuid().v4();
    await registerDevice(driver1, deviceId);
    final fp = firstOf(deviceId);

    final result = await SupabaseFingerprintSender(driver1).send(fp);
    expect(result.status, SendStatus.stored);

    final row = await driver1
        .from('fingerprints')
        .select()
        .eq('device_id', deviceId)
        .eq('seq', 1)
        .single();
    final stored = StoredFingerprint.fromRow(row);
    expect(stored.segmentHash, fp.segmentHash);
    expect(stored.frozen, isFalse);
    expect(stored.receivedAt.difference(DateTime.now()).abs(),
        lessThan(const Duration(minutes: 1)));
  });

  test('renvoyer la même empreinte donne « doublon » (idempotence réelle)', () async {
    final deviceId = const Uuid().v4();
    await registerDevice(driver1, deviceId);
    final sender = SupabaseFingerprintSender(driver1);
    final fp = firstOf(deviceId);

    await sender.send(fp);
    final again = await sender.send(fp);

    expect(again.status, SendStatus.duplicate);
  });

  test('une empreinte pour le téléphone d\'un autre conducteur est refusée', () async {
    final otherDevice = const Uuid().v4();
    await registerDevice(driver2, otherDevice);

    final result = await SupabaseFingerprintSender(driver1).send(firstOf(otherDevice));

    expect(result.status, SendStatus.rejected);
    expect(result.message, isNotNull);
  });

  test('un serveur injoignable donne une erreur réseau', () async {
    final unreachable = SupabaseClient('http://127.0.0.1:59999', publishableKey);

    final result =
        await SupabaseFingerprintSender(unreachable).send(firstOf(const Uuid().v4()));

    expect(result.status, SendStatus.networkError);
    await unreachable.dispose();
  });

  test('TI-10 : l\'envoyeur vide une file réelle vers Supabase', () async {
    final deviceId = const Uuid().v4();
    await registerDevice(driver1, deviceId);

    final store = await LocalStore.open(await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    ));
    var fp = firstOf(deviceId);
    await store.recordSegment(fp);
    for (var i = 0; i < 2; i++) {
      fp = fp.next(
        segmentHash: 'b' * 64,
        startedAt: fp.endedAt,
        endedAt: fp.endedAt.add(const Duration(seconds: 10)),
      );
      await store.recordSegment(fp);
    }

    final report =
        await Uploader(store: store, sender: SupabaseFingerprintSender(driver1)).flush();

    expect(report.remaining, 0);
    final rows = await driver1.from('fingerprints').select('seq').eq('device_id', deviceId);
    expect(rows, hasLength(3));
  });
}