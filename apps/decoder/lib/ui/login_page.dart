import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'palette.dart';
import 'brand_pattern.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final client = Supabase.instance.client;
    try {
      await client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );

      // Le décodeur est réservé aux agents d'assurance.
      final profile = await client
          .from('profiles')
          .select('role')
          .eq('id', client.auth.currentUser!.id)
          .single();
      if (profile['role'] != 'agent') {
        await client.auth.signOut();
        _error = 'Ce compte n\'est pas un compte d\'agent d\'assurance.';
      }
    } on AuthException {
      _error = 'Email ou mot de passe incorrect.';
    } on Exception {
      _error = 'Connexion impossible. Vérifiez votre réseau.';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < compactWidth;
    return Scaffold(
      backgroundColor: Palette.background,
      body: Stack(children: [
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 280,
          child: ColoredBox(
            color: Palette.teal,
            child: CustomPaint(painter: BrandPattern()),
          ),
        ),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 912),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(Icons.shield, size: 22, color: Palette.teal),
                      ),
                      const SizedBox(width: 12),
                      const Text('PreuvCam Assureur',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                    ]),
                    const SizedBox(height: 56),
                    _card(compact),
                  ],
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  /// Grande carte : présentation à gauche, formulaire à droite.
  /// Sur un écran étroit, les deux parties s'empilent.
  Widget _card(bool compact) {
    final intro = Padding(
        padding: EdgeInsets.all(compact ? 24 : 44), child: _Intro(compact: compact));
    final form = Container(
      color: compact ? Colors.white : Palette.panel,
      padding: EdgeInsets.all(compact ? 24 : 44),
      child: _form(),
    );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x1F13201E), blurRadius: 40, offset: Offset(0, 12)),
        ],
      ),
      child: compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              intro,
              const Divider(height: 1, color: Palette.border),
              form,
            ])
          : IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: intro),
                const VerticalDivider(width: 1, color: Palette.track),
                Expanded(child: form),
              ]),
            ),
    );
  }

  Widget _form() {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Palette.border),
    );
    InputDecoration field(String label, IconData icon) => InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Palette.muted),
          filled: true,
          fillColor: Colors.white,
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
              borderSide: const BorderSide(color: Palette.teal, width: 2)),
        );

    return AutofillGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Connexion',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Palette.ink)),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            decoration: field('Email', Icons.mail_outline),
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            decoration: field('Mot de passe', Icons.lock_outline),
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _signIn(),
          ),
          const SizedBox(height: 16),
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Palette.errorBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_error!, style: const TextStyle(fontSize: 13, color: Palette.errorFg)),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: _loading ? null : _signIn,
            style: FilledButton.styleFrom(
              backgroundColor: Palette.teal,
              minimumSize: const Size.fromHeight(48),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Se connecter'),
          ),
          const SizedBox(height: 14),
          const Text(
            'Accès réservé aux agents d\'assurance. '
            'Les comptes sont créés par l\'opérateur de la plateforme.',
            style: TextStyle(fontSize: 13, height: 1.5, color: Palette.muted),
          ),
        ],
      ),
    );
  }
}

//// Colonne de présentation : ce que permet l'espace assureur.
class _Intro extends StatelessWidget {
  const _Intro({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Vérifiez les vidéos de vos assurés',
            style: TextStyle(
                fontSize: 30, height: 1.2, fontWeight: FontWeight.w700, color: Palette.ink)),
        const SizedBox(height: 14),
        const Text(
          'Après un accident, vérifiez en quelques secondes que les segments remis '
          'par le conducteur n\'ont pas été modifiés depuis leur enregistrement.',
          style: TextStyle(fontSize: 16, height: 1.55, color: Palette.muted),
        ),
        const SizedBox(height: 22),
        const _Point(
          icon: Icons.verified_user_outlined,
          text: 'Chaque segment est comparé à l\'empreinte envoyée au moment du tournage.',
        ),
        const SizedBox(height: 14),
        _Point(
          icon: compact ? Icons.smartphone_outlined : Icons.computer_outlined,
          text: 'Les vidéos restent sur votre ${compact ? 'appareil' : 'ordinateur'} : '
              'seule leur empreinte est calculée.',
        ),
        const SizedBox(height: 14),
        const _Point(
          icon: Icons.lock_outline,
          text: 'Vous ne voyez que les téléphones et les empreintes de votre compagnie.',
        ),
      ],
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Palette.tealLight,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 18, color: Palette.teal),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(text,
            style: const TextStyle(fontSize: 15, height: 1.45, color: Palette.body)),
      ),
    ]);
  }
}