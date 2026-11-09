import 'package:dashcam_core/dashcam_core.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_fingerprint_repository.dart';
import '../verification_service.dart';
import 'verdict_style.dart';

class VerificationPage extends StatefulWidget {
  const VerificationPage({super.key});

  @override
  State<VerificationPage> createState() => _VerificationPageState();
}

class _VerificationPageState extends State<VerificationPage>
    with AutomaticKeepAliveClientMixin {
  final _service = VerificationService(
    repository: SupabaseFingerprintRepository(Supabase.instance.client),
  );

  List<SegmentResult> _results = const [];
  (int, int)? _progress;
  Duration? _duration;
  bool _busy = false;
  String? _error;

  /// Conserve les résultats quand l'agent passe d'un onglet à l'autre.
  @override
  bool get wantKeepAlive => true;

Future<void> _pickAndVerify() async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
      _results = const [];
      _progress = (0, files.length);
    });

    final stopwatch = Stopwatch()..start();
    try {
      final results = await _service.verify(
        [
          for (final file in files)
            PickedSegment(fileName: file.name, content: file.readAsByteStream()),
        ],
        onProgress: (done, total) {
          if (mounted) setState(() => _progress = (done, total));
        },
      );
      if (mounted) {
        setState(() {
          _results = results;
          _duration = stopwatch.elapsed;
        });
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _error = 'Vérification impossible : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _freeze() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Geler ces empreintes ?'),
        content: const Text(
            'Les empreintes de référence de ces segments ne seront plus jamais '
            'purgées. Cette action est irréversible.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Geler')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final count = await _service.freeze(_results);
      messenger.showSnackBar(SnackBar(content: Text('$count empreinte(s) gelée(s).')));
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Gel impossible : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final canFreeze = !_busy && _results.any((r) => r.verdict != Verdict.unknown);
    final progress = _progress;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 12, runSpacing: 8, children: [
            FilledButton.icon(
              onPressed: _busy ? null : _pickAndVerify,
              icon: const Icon(Icons.video_file),
              label: const Text('Choisir les vidéos'),
            ),
            OutlinedButton.icon(
              onPressed: canFreeze ? _freeze : null,
              icon: const Icon(Icons.ac_unit),
              label: const Text('Geler ces empreintes'),
            ),
          ]),
          const SizedBox(height: 16),
          if (_busy && progress != null) ...[
            LinearProgressIndicator(
                value: progress.$2 == 0 ? null : progress.$1 / progress.$2),
            const SizedBox(height: 4),
            Text('Calcul des empreintes : ${progress.$1} / ${progress.$2} fichier(s)'),
          ],
          if (_error != null)
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (_results.isNotEmpty) ...[
            _Summary(results: _results, duration: _duration),
            const SizedBox(height: 8),
            Expanded(child: _ResultsTable(results: _results)),
          ],
          if (!_busy && _results.isEmpty && _error == null)
            const Expanded(
              child: Center(
                child: Text(
                  'Choisissez les fichiers vidéo remis par le conducteur.\n'
                  'Ils restent sur cet ordinateur : seule leur empreinte est calculée.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Nombre de fichiers par verdict, et durée de la vérification.
class _Summary extends StatelessWidget {
  const _Summary({required this.results, required this.duration});

  final List<SegmentResult> results;
  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    final elapsed = duration;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final verdict in Verdict.values)
          if (results.any((r) => r.verdict == verdict))
            Chip(
              avatar: Icon(verdict.icon, color: verdict.color),
              label: Text(
                  '${verdict.label} : ${results.where((r) => r.verdict == verdict).length}'),
            ),
        if (elapsed != null)
          Text('Vérifié en ${(elapsed.inMilliseconds / 1000).toStringAsFixed(1)} s'),
      ],
    );
  }
}

/// Tableau des résultats : un fichier par ligne.
class _ResultsTable extends StatelessWidget {
  const _ResultsTable({required this.results});

  final List<SegmentResult> results;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Segment')),
            DataColumn(label: Text('Verdict')),
            DataColumn(label: Text('Alertes')),
            DataColumn(label: Text('Explication')),
          ],
          rows: [
            for (final r in results)
              DataRow(cells: [
                DataCell(Tooltip(
                    message: r.fileName, child: Text(shortSegmentName(r.fileName)))),
                DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(r.verdict.icon, color: r.verdict.color, size: 18),
                  const SizedBox(width: 6),
                  Text(r.verdict.label,
                      style: TextStyle(
                          color: r.verdict.color, fontWeight: FontWeight.bold)),
                ])),
                DataCell(Text(r.alerts.isEmpty
                    ? 'Aucune'
                    : r.alerts.map((a) => a.label).join(', '))),
                DataCell(SizedBox(width: 420, child: Text(r.reason))),
              ]),
          ],
        ),
      ),
    );
  }
}