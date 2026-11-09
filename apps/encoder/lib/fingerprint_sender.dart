import 'package:dashcam_core/dashcam_core.dart';

/// Issue possible de l'envoi d'une empreinte au serveur.
enum SendStatus {
  /// L'empreinte vient d'être enregistrée.
  stored,

  /// L'empreinte était déjà enregistrée (réponse d'un envoi précédent perdue).
  duplicate,

  /// Serveur injoignable : réessayer plus tard.
  networkError,

  /// Le serveur refuse l'empreinte : erreur à signaler, pas à réessayer.
  rejected,
}

/// Résultat d'un envoi, avec un message en cas de refus.
class SendResult {
  const SendResult(this.status, [this.message]);

  final SendStatus status;
  final String? message;
}

/// Envoie une empreinte au serveur. Une implémentation ne lève jamais
/// d'exception : toute issue est traduite en [SendResult].
abstract interface class FingerprintSender {
  Future<SendResult> send(Fingerprint fp);
}