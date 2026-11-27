import 'package:dashcam_core/dashcam_core.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'palette.dart';
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
    final compact = MediaQuery.sizeOf(context).width < compactWidth;
    final pad = compact ? 16.0 : 24.0;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _stream,
          builder: (context, snapshot) {
            final fingerprints = snapshot.hasData
                ? snapshot.data!.map(StoredFingerprint.fromRow).toList()
                : const <StoredFingerprint>[];
            return ListView(
              padding: EdgeInsets.fromLTRB(pad, compact ? 18 : 28, pad, 40),
              children: [
                _Intro(compact: compact, live: snapshot.hasData && !snapshot.hasError),
                const SizedBox(height: 20),
                if (snapshot.hasError)
                  _Message(
                    icon: Icons.cloud_off,
                    text: 'Connexion temps réel impossible : ${snapshot.error}',
                    error: true,
                  )
                else if (!snapshot.hasData)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator(color: Palette.teal)),
                  )
                else if (fingerprints.isEmpty)
                  const _Message(
                      icon: Icons.sensors, text: 'Aucune empreinte reçue pour l\'instant.')
                else
                  for (final fp in fingerprints) ...[
                    _FingerprintCard(fp),
                    const SizedBox(height: 10),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Titre, explication et état de la connexion temps réel.
class _Intro extends StatelessWidget {
  const _Intro({required this.compact, required this.live});

  final bool compact;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text('Suivi en direct',
                style: TextStyle(
                    fontSize: compact ? 24 : 28,
                    fontWeight: FontWeight.w700,
                    color: Palette.ink)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: live ? Palette.okBg : Palette.neutralBg,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.circle, size: 9, color: live ? Palette.okFg : Palette.muted),
              const SizedBox(width: 6),
              Text(live ? 'En direct' : 'Connexion…',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: live ? Palette.okFg : Palette.muted)),
            ]),
          ),
        ]),
        const SizedBox(height: 6),
        const Text(
          'Les 30 dernières empreintes reçues des téléphones de la compagnie, '
          'mises à jour en temps réel.',
          style: TextStyle(fontSize: 15, color: Palette.muted),
        ),
      ],
    );
  }
}

/// Une empreinte reçue : segment, période filmée, réception et début du hash.
class _FingerprintCard extends StatelessWidget {
  const _FingerprintCard(this.fp);

  final StoredFingerprint fp;

  static String _clock(DateTime t) {
    final local = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final name = SegmentName(deviceId: fp.deviceId, seq: fp.seq).fileName;
    final delay =
        (fp.deliveryDelay.inMilliseconds / 1000).toStringAsFixed(1).replaceAll('.', ',');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Palette.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Palette.tealLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(fp.frozen ? Icons.ac_unit : Icons.fingerprint, color: Palette.teal),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(shortSegmentName(name),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600, color: Palette.ink)),
                if (fp.frozen)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Palette.neutralBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text('Gelée',
                        style: TextStyle(fontSize: 12, color: Palette.neutralFg)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Filmé de ${_clock(fp.startedAt)} à ${_clock(fp.endedAt)} · '
              'reçu à ${_clock(fp.receivedAt)} (délai $delay s)',
              style: const TextStyle(fontSize: 13, color: Palette.body),
            ),
            const SizedBox(height: 2),
            Text('Empreinte ${fp.segmentHash.substring(0, 16)}…',
                style: const TextStyle(
                    fontSize: 12, color: Palette.muted, fontFamily: 'monospace')),
          ]),
        ),
      ]),
    );
  }
}

/// Message d'état : erreur de connexion ou liste vide.
class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.error = false});

  final IconData icon;
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final fg = error ? Palette.errorFg : Palette.muted;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: error ? Palette.errorBg : Colors.white,
        border: Border.all(color: error ? Palette.errorBg : Palette.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Icon(icon, color: fg),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: TextStyle(color: fg))),
      ]),
    );
  }
}