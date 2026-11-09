import 'package:crypto/crypto.dart';

/// Calcule le SHA-256 d'un contenu fourni sous forme de flux d'octets.
///
/// Le flux peut venir d'un fichier du téléphone ou d'un fichier choisi dans
/// le navigateur : la fonction ne dépend pas de `dart:io`.
/// Renvoie l'empreinte en hexadécimal minuscule (64 caractères).
Future<String> sha256OfStream(Stream<List<int>> bytes) async {
  final digest = await sha256.bind(bytes).first;
  return digest.toString();
}