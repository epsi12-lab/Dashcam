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

      // L'encodeur est réservé aux conducteurs.
      final profile = await client
          .from('profiles')
          .select('role')
          .eq('id', client.auth.currentUser!.id)
          .single();
      if (profile['role'] != 'driver') {
        await client.auth.signOut();
        _error = 'Ce compte n\'est pas un compte de conducteur.';
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
    return Scaffold(
      backgroundColor: Palette.background,
      body: Stack(
        children: [
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 300,
            child: ColoredBox(
              color: Palette.teal,
              child: CustomPaint(painter: BrandPattern()),
            ),
          ),
          SafeArea(
            // Défilable : clavier ouvert, la hauteur disponible sur un téléphone est réduite.
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.shield,
                          size: 40,
                          color: Palette.teal,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'PreuvCam',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Votre dashcam, preuve à l\'appui',
                        style: TextStyle(fontSize: 15, color: Colors.white70),
                      ),
                      const SizedBox(height: 36),
                      Container(
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x1F13201E),
                              blurRadius: 40,
                              offset: Offset(0, 12),
                            ),
                          ],
                        ),
                        child: _form(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
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
        borderSide: const BorderSide(color: Palette.teal, width: 2),
      ),
    );

    return AutofillGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Espace conducteur',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Palette.ink,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Connectez-vous avec le compte remis par votre assureur.',
            style: TextStyle(fontSize: 14, height: 1.45, color: Palette.muted),
          ),
          const SizedBox(height: 18),
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
              child: Text(
                _error!,
                style: const TextStyle(fontSize: 13, color: Palette.errorFg),
              ),
            ),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: _loading ? null : _signIn,
            style: FilledButton.styleFrom(
              backgroundColor: Palette.teal,
              minimumSize: const Size.fromHeight(50),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Se connecter'),
          ),
        ],
      ),
    );
  }
}
