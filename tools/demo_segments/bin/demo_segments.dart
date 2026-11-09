import 'dart:io';
import 'dart:math';

import 'package:dashcam_core/dashcam_core.dart';
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

/// Simulateur d'encodeur pour la démonstration : produit des segments
/// factices au rythme réel et envoie leurs empreintes à Supabase.
///
/// Options : --count N (5), --duration S (10), --out DOSSIER (demo_videos),
/// --late (le dernier envoi est retardé de 40 s).
Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final url = env['SUPABASE_URL'] ?? 'http://127.0.0.1:54321';
  final key = env['SUPABASE_KEY'] ?? 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';
  final email = env['DEMO_EMAIL'] ?? 'conducteur1@alpha.test';
  final password = env['DEMO_PASSWORD'] ?? 'dashcam-demo';

  final count = int.parse(_option(args, '--count') ?? '5');
  final duration = Duration(seconds: int.parse(_option(args, '--duration') ?? '10'));
  final outDir = Directory(_option(args, '--out') ?? 'demo_videos');
  final late = args.contains('--late');

  final client = SupabaseClient(url, key);
  await client.auth.signInWithPassword(email: email, password: password);

  final deviceId = const Uuid().v4();
  await client.from('devices').insert({
    'id': deviceId,
    'owner_id': client.auth.currentUser!.id,
  });
  stdout.writeln('Téléphone simulé : $deviceId');

  await outDir.create(recursive: true);
  final random = Random.secure();
  var start = DateTime.now().toUtc();
  Fingerprint? fp;

  for (var seq = 1; seq <= count; seq++) {
    final end = start.add(duration);

    // « Enregistrement » : un fichier de 1 Mo d'octets aléatoires.
    final name = SegmentName(deviceId: deviceId, seq: seq).fileName;
    final file = File('${outDir.path}/$name');
    await file.writeAsBytes(List<int>.generate(1024 * 1024, (_) => random.nextInt(256)));
    final hash = await sha256OfStream(file.openRead());

    fp = fp == null
        ? Fingerprint.first(deviceId: deviceId, segmentHash: hash, startedAt: start, endedAt: end)
        : fp.next(segmentHash: hash, startedAt: start, endedAt: end);

    // On attend la fin réelle du segment, comme une vraie dashcam.
    final wait = end.difference(DateTime.now().toUtc());
    if (!wait.isNegative) await Future<void>.delayed(wait);

    if (late && seq == count) {
      stdout.writeln('Coupure simulée : dernier envoi retardé de 40 s...');
      await Future<void>.delayed(const Duration(seconds: 40));
    }

    await client.from('fingerprints').insert(fp.toInsertJson());
    stdout.writeln('Segment $seq envoyé : ${file.path}');
    start = end;
  }

  await client.dispose();
}

/// Valeur qui suit [name] dans les arguments, ou null.
String? _option(List<String> args, String name) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}