import 'package:dashcam_core/dashcam_core.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_fingerprint_repository.dart';
import '../verification_service.dart';
import 'palette.dart';
import 'verdict_style.dart';
import 'video_dialog.dart';

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
  List<PlatformFile> _files = const [];
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
      _files = files;
      _progress = (0, files.length);
    });

    final stopwatch = Stopwatch()..start();
    try {
      final results = await _service.verify(
        [
          for (final file in files)
            PickedSegment(
              fileName: file.name,
              content: file.readAsByteStream(),
            ),
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
          'purgées. Cette action est irréversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Geler'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final count = await _service.freeze(_results);
      messenger.showSnackBar(
        SnackBar(content: Text('$count empreinte(s) gelée(s).')),
      );
    } on Exception catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Gel impossible : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final canFreeze =
        !_busy && _results.any((r) => r.verdict != Verdict.unknown);
    final progress = _progress;

    // La largeur de la fenêtre, et non un `LayoutBuilder` : passer du tableau
    // aux cartes est alors une reconstruction normale, et non une
    // modification de l'arbre en pleine mise en page.
    final compact = MediaQuery.sizeOf(context).width < compactWidth;
    final pad = compact ? 16.0 : 24.0;

    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, compact ? 18 : 28, pad, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Intro(
                  compact: compact,
                  busy: _busy,
                  canFreeze: canFreeze,
                  onPick: _pickAndVerify,
                  onFreeze: _freeze,
                ),
                const SizedBox(height: 20),
                if (_busy && progress != null) ...[
                  LinearProgressIndicator(
                    value: progress.$2 == 0 ? null : progress.$1 / progress.$2,
                    color: Palette.teal,
                    backgroundColor: Palette.track,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Calcul des empreintes : ${progress.$1} / ${progress.$2} fichier(s)',
                    style: const TextStyle(color: Palette.muted),
                  ),
                  const SizedBox(height: 20),
                ],
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Palette.errorBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Palette.errorFg),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                if (_results.isNotEmpty) ...[
                  _Summary(results: _results, compact: compact),
                  const SizedBox(height: 20),
                  if (compact)
                    _ResultCards(
                      results: _results,
                      files: _files,
                      duration: _duration,
                    )
                  else
                    _ResultsTable(
                      results: _results,
                      files: _files,
                      duration: _duration,
                    ),
                ] else if (!_busy && _error == null)
                  const _EmptyState(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Titre, phrase de confidentialité et deux actions.
class _Intro extends StatelessWidget {
  const _Intro({
    required this.compact,
    required this.busy,
    required this.canFreeze,
    required this.onPick,
    required this.onFreeze,
  });

  final bool compact;
  final bool busy;
  final bool canFreeze;
  final VoidCallback onPick;
  final VoidCallback onFreeze;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    const label = TextStyle(fontSize: 15, fontWeight: FontWeight.w600);
    final pick = FilledButton.icon(
      onPressed: busy ? null : onPick,
      style: FilledButton.styleFrom(
        backgroundColor: Palette.teal,
        minimumSize: const Size(0, 48),
        shape: shape,
        textStyle: label,
      ),
      icon: const Icon(Icons.video_file_outlined),
      label: const Text('Choisir les vidéos'),
    );
    final freeze = OutlinedButton.icon(
      onPressed: canFreeze ? onFreeze : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: Palette.teal,
        minimumSize: const Size(0, 48),
        side: BorderSide(color: canFreeze ? Palette.teal : Palette.border),
        shape: shape,
        textStyle: label,
      ),
      icon: const Icon(Icons.ac_unit),
      label: const Text('Geler ces empreintes'),
    );
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Vérifier des vidéos',
          style: TextStyle(
            fontSize: compact ? 24 : 28,
            fontWeight: FontWeight.w700,
            color: Palette.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Les fichiers restent sur cet ${compact ? 'appareil' : 'ordinateur'} : '
          'seule leur empreinte est calculée et comparée.',
          style: const TextStyle(fontSize: 15, color: Palette.muted),
        ),
      ],
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          text,
          const SizedBox(height: 14),
          pick,
          const SizedBox(height: 10),
          freeze,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: text),
        const SizedBox(width: 16),
        pick,
        const SizedBox(width: 12),
        freeze,
      ],
    );
  }
}

/// Compteurs par verdict, plus les alertes sur grand écran.
class _Summary extends StatelessWidget {
  const _Summary({required this.results, required this.compact});

  final List<SegmentResult> results;
  final bool compact;

  static String _plural(Verdict v) => switch (v) {
    Verdict.authentic => 'Authentiques',
    Verdict.modified => 'Modifiés',
    Verdict.inconsistent => 'Incohérents',
    Verdict.unknown => 'Inconnus',
  };

  /// Ordre d'affichage de la maquette : du plus rassurant au plus inquiétant
  /// pour l'intégrité, puis les fichiers sans référence.
  static const _order = [
    Verdict.authentic,
    Verdict.modified,
    Verdict.inconsistent,
    Verdict.unknown,
  ];

  @override
  Widget build(BuildContext context) {
    final items = [
      for (final v in _order)
        (
          label: _plural(v),
          value: results.where((r) => r.verdict == v).length,
          color: v.accent,
        ),
      if (!compact)
        (
          label: 'Alertes',
          value: results.where((r) => r.alerts.isNotEmpty).length,
          color: Palette.teal,
        ),
    ];
    const gap = 12.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = compact ? 2 : items.length;
        // Pendant un redimensionnement, la largeur disponible peut valoir 0 :
        // la largeur d'une carte ne doit jamais devenir négative.
        final width = ((constraints.maxWidth - gap * (columns - 1)) / columns)
            .clamp(0.0, double.infinity);
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 12 : 16,
                    vertical: compact ? 10 : 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Palette.border),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: item.color,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            item.label,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Palette.muted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${item.value}',
                        style: TextStyle(
                          fontSize: compact ? 22 : 28,
                          fontWeight: FontWeight.w700,
                          color: Palette.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Ligne de synthèse : nombre de fichiers et durée de la vérification.
String _overview(List<SegmentResult> results, Duration? duration) {
  final n = results.length;
  final parts = ['$n ${n > 1 ? 'fichiers' : 'fichier'}'];
  if (duration != null) {
    final s = (duration.inMilliseconds / 1000)
        .toStringAsFixed(1)
        .replaceAll('.', ',');
    parts.add('vérifié en $s s');
  }
  return parts.join(' · ');
}

String _alertsText(SegmentResult r) =>
    r.alerts.isEmpty ? 'Aucune' : r.alerts.map((a) => a.label).join(', ');

String _two(int n) => n.toString().padLeft(2, '0');

/// Période filmée en heure locale, ou `null` si elle est inconnue.
String? _period(SegmentResult r) {
  final start = r.startedAt;
  final end = r.endedAt;
  if (start == null || end == null) return null;
  String t(DateTime d) {
    final l = d.toLocal();
    return '${_two(l.hour)}:${_two(l.minute)}:${_two(l.second)}';
  }

  return '${t(start)} à ${t(end)}';
}

Future<void> _openVideo(
  BuildContext context,
  SegmentResult r,
  PlatformFile file,
) => showDialog<void>(
  context: context,
  builder: (_) =>
      VideoDialog(fileName: r.fileName, loadBytes: file.readAsBytes),
);

/// Grand écran : tableau, un fichier par ligne.
class _ResultsTable extends StatelessWidget {
  const _ResultsTable({
    required this.results,
    required this.files,
    required this.duration,
  });

  final List<SegmentResult> results;

  /// Fichiers choisis, dans le même ordre que les résultats.
  final List<PlatformFile> files;
  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Palette.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Text(
              _overview(results, duration),
              style: const TextStyle(fontSize: 14, color: Palette.muted),
            ),
          ),
          const Divider(height: 1, color: Palette.border),
          LayoutBuilder(
            builder: (context, constraints) {
              final minWidth = constraints.maxWidth < 880
                  ? 880.0
                  : constraints.maxWidth;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: minWidth),
                  child: DataTable(
                    headingRowColor: const WidgetStatePropertyAll(
                      Color(0xFFF7FAF9),
                    ),
                    headingTextStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Palette.muted,
                    ),
                    dataRowMinHeight: 64,
                    dataRowMaxHeight: 84,
                    columns: const [
                      DataColumn(label: Text('Segment')),
                      DataColumn(label: Text('Verdict')),
                      DataColumn(label: Text('Alertes')),
                      DataColumn(label: Text('Explication')),
                      DataColumn(label: Text('Vidéo')),
                    ],
                    rows: [
                      for (var i = 0; i < results.length; i++)
                        _row(
                          context,
                          results[i],
                          i < files.length ? files[i] : null,
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  DataRow _row(
    BuildContext context,
    SegmentResult r,
    PlatformFile? file,
  ) => DataRow(
    cells: [
      DataCell(
        Tooltip(
          message: r.fileName,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                shortSegmentName(r.fileName),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Palette.ink,
                ),
              ),
              if (_period(r) case final period?)
                Text(
                  period,
                  style: const TextStyle(fontSize: 13, color: Palette.muted),
                ),
            ],
          ),
        ),
      ),
      DataCell(_VerdictBadge(r.verdict)),
      DataCell(
        Text(
          _alertsText(r),
          style: TextStyle(
            color: r.alerts.isEmpty ? Palette.muted : Palette.warnFg,
          ),
        ),
      ),
      DataCell(
        SizedBox(
          width: 420,
          child: Text(r.reason, style: const TextStyle(color: Palette.body)),
        ),
      ),
      DataCell(
        file == null
            ? const SizedBox.shrink()
            : IconButton.outlined(
                tooltip: 'Visionner',
                onPressed: () => _openVideo(context, r, file),
                icon: const Icon(Icons.play_arrow, size: 20),
                style: IconButton.styleFrom(
                  foregroundColor: Palette.ink,
                  minimumSize: const Size(44, 44),
                  side: const BorderSide(color: Palette.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
      ),
    ],
  );
}

/// Téléphone : une carte par fichier.
class _ResultCards extends StatelessWidget {
  const _ResultCards({
    required this.results,
    required this.files,
    required this.duration,
  });

  final List<SegmentResult> results;
  final List<PlatformFile> files;
  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    final alerts = results.where((r) => r.alerts.isNotEmpty).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${_overview(results, duration)} · '
          '$alerts ${alerts > 1 ? 'alertes' : 'alerte'}',
          style: const TextStyle(fontSize: 13, color: Palette.muted),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < results.length; i++) ...[
          _card(context, results[i], i < files.length ? files[i] : null),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _card(BuildContext context, SegmentResult r, PlatformFile? file) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Palette.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shortSegmentName(r.fileName),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Palette.ink,
                      ),
                    ),
                    if (_period(r) case final period?)
                      Text(
                        period,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Palette.muted,
                        ),
                      ),
                  ],
                ),
              ),
              _VerdictBadge(r.verdict),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            r.reason,
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: Palette.body,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  r.alerts.isEmpty ? 'Aucune alerte' : _alertsText(r),
                  style: TextStyle(
                    fontSize: 12,
                    color: r.alerts.isEmpty ? Palette.muted : Palette.warnFg,
                  ),
                ),
              ),
              if (file != null)
                OutlinedButton.icon(
                  onPressed: () => _openVideo(context, r, file),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Palette.ink,
                    minimumSize: const Size(0, 44),
                    side: const BorderSide(color: Palette.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Lire'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Étiquette d'un verdict : fond, icône et libellé.
class _VerdictBadge extends StatelessWidget {
  const _VerdictBadge(this.verdict);

  final Verdict verdict;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: verdict.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(verdict.icon, size: 14, color: verdict.color),
          const SizedBox(width: 5),
          Text(
            verdict.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: verdict.color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Avant toute vérification : indications sur la marche à suivre.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Palette.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        children: [
          Icon(Icons.video_library_outlined, size: 40, color: Palette.teal),
          SizedBox(height: 12),
          Text(
            'Aucune vidéo vérifiée pour l\'instant',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Palette.ink,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Choisissez les fichiers vidéo remis par le conducteur.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Palette.muted),
          ),
        ],
      ),
    );
  }
}
