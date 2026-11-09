import 'package:dashcam_core/dashcam_core.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'verdict_style.dart';

/// Empreintes reçues en temps réel des téléphones de la compagnie.
class LivePage extends StatefulWidget {
  const LivePage({super.key});

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> with AutomaticKeepAliveClientMixin {
  /// Flux créé une seule fois : chargement initial, puis mises à jour en direct.
  final _stream = Supabase.instance.client
      .from('fingerprints')
      .stream(primaryKey: ['id'])
      .order('received_at', ascending: false)
      .limit(30);

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Connexion temps réel impossible : ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final fingerprints = snapshot.data!.map(StoredFingerprint.fromRow).toList();
        if (fingerprints.isEmpty) {
          return const Center(child: Text('Aucune empreinte reçue pour l\'instant.'));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${fingerprints.length} dernières empreintes reçues, mises à jour en temps réel',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: fingerprints.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) => _FingerprintTile(fingerprints[i]),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FingerprintTile extends StatelessWidget {
  const _FingerprintTile(this.fp);

  final StoredFingerprint fp;

  @override
  Widget build(BuildContext context) {
    final name = SegmentName(deviceId: fp.deviceId, seq: fp.seq).fileName;
    final delay = fp.deliveryDelay.inMilliseconds / 1000;
    return ListTile(
      leading: Icon(fp.frozen ? Icons.ac_unit : Icons.fingerprint),
      title: Text(shortSegmentName(name)),
      subtitle: Text(
          'Reçue à ${_clock(fp.receivedAt)}, délai ${delay.toStringAsFixed(1)} s, '
          'empreinte ${fp.segmentHash.substring(0, 12)}…'),
      trailing: fp.frozen ? const Text('Gelée') : null,
    );
  }

  static String _clock(DateTime t) {
    final local = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}