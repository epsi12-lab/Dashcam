import 'fingerprint_sender.dart';
import 'local_store.dart';

/// Bilan d'un vidage de la file d'attente.
class FlushReport {
  const FlushReport({
    required this.sent,
    required this.remaining,
    this.networkUnavailable = false,
    this.error,
  });

  /// Empreintes retirées de la file pendant ce vidage.
  final int sent;

  /// Empreintes encore en attente à la fin du vidage.
  final int remaining;

  /// Le vidage s'est arrêté faute de réseau.
  final bool networkUnavailable;

  /// Message à afficher si une empreinte a été refusée.
  final String? error;
}

/// Vide la file d'attente vers le serveur, dans l'ordre des numéros.
class Uploader {
  Uploader({required this.store, required this.sender});

  final LocalStore store;
  final FingerprintSender sender;

  /// Vidage en cours, s'il y en a un.
  Future<FlushReport>? _running;

  /// Lance un vidage, ou rejoint celui qui est déjà en cours.
  ///
  /// Une empreinte ajoutée pendant un vidage sera envoyée au vidage suivant.
  Future<FlushReport> flush() =>
      _running ??= _flush().whenComplete(() => _running = null);

  Future<FlushReport> _flush() async {
    var sent = 0;

    for (final fp in await store.pendingUploads()) {
      final result = await sender.send(fp);

      switch (result.status) {
        case SendStatus.stored || SendStatus.duplicate:
          await store.markUploaded(fp.seq);
          sent++;

        case SendStatus.networkError:
          return FlushReport(
            sent: sent,
            remaining: await store.pendingCount(),
            networkUnavailable: true,
          );

        case SendStatus.rejected:
          return FlushReport(
            sent: sent,
            remaining: await store.pendingCount(),
            error: 'Empreinte ${fp.seq} refusée : ${result.message ?? 'raison inconnue'}',
          );
      }
    }

    return FlushReport(sent: sent, remaining: await store.pendingCount());
  }
}