import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'palette.dart';

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

    return Scaffold(
      backgroundColor: Palette.background,
      body: SafeArea(
        child: Center(
          // Défilable : clavier ouvert, il reste peu de hauteur sur un téléphone.
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Palette.border),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: AutofillGroup(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Palette.teal,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.shield, size: 34, color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('PreuvCam Assureur',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w700, color: Palette.ink)),
                      const SizedBox(height: 4),
                      const Text('Espace assureur',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: Palette.muted)),
                      const SizedBox(height: 24),
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
                          child: Text(_error!,
                              style: const TextStyle(fontSize: 13, color: Palette.errorFg)),
                        ),
                        const SizedBox(height: 12),
                      ],
                      FilledButton(
                        onPressed: _loading ? null : _signIn,
                        style: FilledButton.styleFrom(
                          backgroundColor: Palette.teal,
                          minimumSize: const Size.fromHeight(48),
                          textStyle:
                              const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _loading
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Se connecter'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}