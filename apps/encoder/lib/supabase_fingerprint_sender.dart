import 'dart:async';

import 'package:dashcam_core/dashcam_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fingerprint_sender.dart';

/// Envoie les empreintes à la table `fingerprints` de Supabase.
class SupabaseFingerprintSender implements FingerprintSender {
  SupabaseFingerprintSender(this._client, {this.timeout = const Duration(seconds: 15)});

  final SupabaseClient _client;

  /// Délai au-delà duquel on considère que le serveur ne répond pas.
  final Duration timeout;

  /// Familles d'erreurs SQL définitives : données invalides (22),
  /// contraintes (23), permissions et RLS (42).
  static final _definitive = RegExp(r'^(22|23|42)[0-9A-Z]{3}$');

  @override
  Future<SendResult> send(Fingerprint fp) async {
    try {
      await _client.from('fingerprints').insert(fp.toInsertJson()).timeout(timeout);
      return const SendResult(SendStatus.stored);
    } on PostgrestException catch (e) {
      final code = e.code;
      if (code == '23505') {
        return const SendResult(SendStatus.duplicate);
      }
      if (code != null && _definitive.hasMatch(code)) {
        return SendResult(SendStatus.rejected, '${e.message} ($code)');
      }
      return SendResult(SendStatus.networkError, e.message);
    } on Exception catch (e) {
      // Serveur injoignable, délai dépassé, réponse illisible : on réessaiera.
      return SendResult(SendStatus.networkError, '$e');
    }
  }
}