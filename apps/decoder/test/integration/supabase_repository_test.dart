@Tags(['integration'])
library;

import 'dart:convert';

import 'package:dashcam_core/dashcam_core.dart';
import 'package:dashcam_decoder/supabase_fingerprint_repository.dart';
import 'package:dashcam_decoder/verification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

const url = 'http://127.0.0.1:54321';
const publishableKey = 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';
const password = 'dashcam-demo';

Future<SupabaseClient> signedIn(String email) async {
  final client = SupabaseClient(url, publishableKey);
  await client.auth.signInWithPassword(email: email, password: password);
  return client;
}

Stream<List<int>> bytes(String text) => Stream.value(utf8.encode(text));

const contents = ['vidéo 1', 'vidéo 2', 'vidéo 3'];

void main() {
  late SupabaseClient driver;
  late SupabaseClient agentAlpha;
  late SupabaseClient agentBeta;
  late String deviceId;

  // Le conducteur 1 (Assur Alpha) enregistre un téléphone neuf
  // et envoie trois empreintes chaînées.
  setUpAll(() async {
    driver = await signedIn('conducteur1@alpha.test');
    agentAlpha = await signedIn('agent@alpha.test');
    agentBeta = await signedIn('agent@beta.test');

    deviceId = const Uuid().v4();
    await driver.from('devices').insert({
      'id': deviceId,
      'owner_id': driver.auth.currentUser!.id,
    });

    final end = DateTime.now().toUtc();
    Fingerprint? fp;
    for (var i = 0; i < contents.length; i++) {
      final hash = await sha256OfStream(bytes(contents[i]));
      final start = end.subtract(Duration(seconds: 10 * (contents.length - i)));
      final stop = start.add(const Duration(seconds: 10));
      fp = fp == null
          ? Fingerprint.first(
              deviceId: deviceId, segmentHash: hash, startedAt: start, endedAt: stop)
          : fp.next(segmentHash: hash, startedAt: start, endedAt: stop);
      await driver.from('fingerprints').insert(fp.toInsertJson());
    }
  });

  tearDownAll(() async {
    await driver.dispose();
    await agentAlpha.dispose();
    await agentBeta.dispose();
  });

  test('ENF-09 : l\'agent de la compagnie lit les empreintes, dans l\'ordre', () async {
    final rows = await SupabaseFingerprintRepository(agentAlpha)
        .fetchRange(deviceId: deviceId, fromSeq: 1, toSeq: 3);

    expect(rows.map((r) => r.seq), [1, 2, 3]);
    expect(rows.first.prevHash, isNull);
  });

  test('seule la plage demandée est renvoyée', () async {
    final rows = await SupabaseFingerprintRepository(agentAlpha)
        .fetchRange(deviceId: deviceId, fromSeq: 2, toSeq: 3);

    expect(rows.map((r) => r.seq), [2, 3]);
  });

  test('TA-08 : l\'agent d\'une autre compagnie ne voit rien', () async {
    final rows = await SupabaseFingerprintRepository(agentBeta)
        .fetchRange(deviceId: deviceId, fromSeq: 1, toSeq: 3);

    expect(rows, isEmpty);
  });

  test('TI-07 : l\'agent d\'une autre compagnie ne peut rien geler', () async {
    final frozen = await SupabaseFingerprintRepository(agentBeta)
        .freeze(deviceId: deviceId, seqs: [1, 2, 3]);

    expect(frozen, 0);
  });

  test('EF-D07 : l\'agent de la compagnie gèle les empreintes demandées', () async {
    final repo = SupabaseFingerprintRepository(agentAlpha);

    final frozen = await repo.freeze(deviceId: deviceId, seqs: [1, 2]);
    final rows = await repo.fetchRange(deviceId: deviceId, fromSeq: 1, toSeq: 3);

    expect(frozen, 2);
    expect(rows.map((r) => r.frozen), [true, true, false]);
  });

  test('de bout en bout : les fichiers intacts sont déclarés authentiques', () async {
    final service =
        VerificationService(repository: SupabaseFingerprintRepository(agentAlpha));

    final results = await service.verify([
      for (var i = 0; i < contents.length; i++)
        PickedSegment(
          fileName: SegmentName(deviceId: deviceId, seq: i + 1).fileName,
          content: bytes(contents[i]),
        ),
    ]);

    expect(results.map((r) => r.verdict), everyElement(Verdict.authentic));
  });
}