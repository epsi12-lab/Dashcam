import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'live_page.dart';
import 'palette.dart';
import 'verification_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Palette.background,
        body: SafeArea(
          child: Builder(builder: (context) {
            final compact = MediaQuery.sizeOf(context).width < compactWidth;
            return Column(children: [
              _Header(compact: compact),
              if (compact)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _Sections(compact: true),
                ),
              const Expanded(
                child: TabBarView(children: [VerificationPage(), LivePage()]),
              ),
            ]);
          }),
        ),
      ),
    );
  }
}

/// Bandeau du haut : logo, navigation, compagnie, compte et déconnexion.
class _Header extends StatefulWidget {
  const _Header({required this.compact});

  final bool compact;

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  final _client = Supabase.instance.client;

  /// Chargé une seule fois : le nom ne change pas pendant la session.
  late final Future<String?> _company = _loadCompany();

  /// La RLS ne laisse voir à l'agent que sa propre compagnie.
  Future<String?> _loadCompany() async {
    try {
      final row = await _client.from('insurers').select('name').maybeSingle();
      return row?['name'] as String?;
    } on Exception {
      return null; // l'en-tête s'affiche alors sans le nom
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = _client.auth.currentUser?.email ?? '';
    final logout = IconButton.outlined(
      tooltip: 'Se déconnecter',
      onPressed: _client.auth.signOut,
      icon: const Icon(Icons.logout, size: 20),
      style: IconButton.styleFrom(
        foregroundColor: Palette.ink,
        minimumSize: const Size(44, 44),
        side: const BorderSide(color: Palette.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    final content = widget.compact
        ? Row(children: [
            const _Logo(size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('PreuvCam Assureur',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Palette.ink)),
                FutureBuilder(
                  future: _company,
                  builder: (context, snap) => Text(
                    [if (snap.data != null) snap.data!, email].join(' · '),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Palette.muted),
                  ),
                ),
              ]),
            ),
            logout,
          ])
        : Row(children: [
            const _Logo(size: 32),
            const SizedBox(width: 10),
            const Text('PreuvCam Assureur',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Palette.ink)),
            const SizedBox(width: 24),
            const Expanded(
              child: Align(alignment: Alignment.centerLeft, child: _Sections(compact: false)),
            ),
            FutureBuilder(
              future: _company,
              builder: (context, snap) => snap.data == null
                  ? const SizedBox.shrink()
                  : Container(
                      margin: const EdgeInsets.only(right: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Palette.neutralBg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(snap.data!,
                          style: const TextStyle(fontSize: 13, color: Palette.muted)),
                    ),
            ),
            Text(email, style: const TextStyle(fontSize: 14, color: Palette.ink)),
            const SizedBox(width: 12),
            logout,
          ]);

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Palette.border)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 16 : 24, vertical: widget.compact ? 10 : 12),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Navigation entre les deux sections : pastilles sur grand écran,
/// sélecteur à deux positions sur téléphone.
class _Sections extends StatelessWidget {
  const _Sections({required this.compact});

  final bool compact;

  static const _tabs = [Tab(text: 'Vérification'), Tab(text: 'Suivi en direct')];

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(fontSize: 15, fontWeight: FontWeight.w600);
    if (!compact) {
      return TabBar(
        tabs: _tabs,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerColor: Colors.transparent,
        labelColor: Palette.tealDark,
        unselectedLabelColor: Palette.muted,
        labelStyle: labelStyle,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: Palette.tealLight,
          borderRadius: BorderRadius.circular(10),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Palette.track,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        tabs: _tabs,
        dividerColor: Colors.transparent,
        labelColor: Palette.tealDark,
        unselectedLabelColor: Palette.muted,
        labelStyle: labelStyle,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(9),
        ),
      ),
    );
  }
}

/// Logo : un bouclier blanc sur un carré vert arrondi.
class _Logo extends StatelessWidget {
  const _Logo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Palette.teal,
        borderRadius: BorderRadius.circular(size / 4),
      ),
      child: Icon(Icons.shield, size: size * 0.62, color: Colors.white),
    );
  }
}