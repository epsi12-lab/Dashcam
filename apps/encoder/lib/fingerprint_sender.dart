import 'package:dashcam_core/dashcam_core.dart';

/// Issue possible de l'envoi d'une empreinte au serveur.
enum SendStatus {
  /// L'empreinte vient d'être enregistrée.
  stored,

  /// L'empreinte était déjà enregistrée (la réponse d'un envoi précédent a été perdue).
  duplicate,

  /// Serveur injoignable : l'envoi sera retenté plus tard.
  networkError,

  /// Le serveur refuse l'empreinte : l'erreur doit être signalée, sans nouvel essai.
  rejected,
}

/// Résultat d'un envoi, avec un message en cas de refus.
class SendResult {
  const SendResult(this.status, [this.message]);

  final SendStatus status;
  final String? message;
}

/// Envoie une empreinte au serveur. Une implémentation ne lève jamais
/// d'exception : chaque issue est traduite en [SendResult].
abstract interface class FingerprintSender {
  Future<SendResult> send(Fingerprint fp);
}
