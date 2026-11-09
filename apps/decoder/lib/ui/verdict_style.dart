import 'package:dashcam_core/dashcam_core.dart';
import 'package:flutter/material.dart';

/// Libellé, couleur et icône de chaque verdict. La couleur n'est jamais
/// la seule information : le libellé et l'icône l'accompagnent toujours.
extension VerdictStyle on Verdict {
  String get label => switch (this) {
        Verdict.authentic => 'Authentique',
        Verdict.modified => 'Modifié',
        Verdict.inconsistent => 'Incohérent',
        Verdict.unknown => 'Inconnu',
      };

  Color get color => switch (this) {
        Verdict.authentic => Colors.green.shade700,
        Verdict.modified => Colors.red.shade700,
        Verdict.inconsistent => Colors.orange.shade800,
        Verdict.unknown => Colors.grey.shade600,
      };

  IconData get icon => switch (this) {
        Verdict.authentic => Icons.check_circle,
        Verdict.modified => Icons.cancel,
        Verdict.inconsistent => Icons.warning,
        Verdict.unknown => Icons.help,
      };
}

extension AlertStyle on Alert {
  String get label => switch (this) {
        Alert.lateDelivery => 'Envoi tardif',
        Alert.missingPrevious => 'Segment précédent manquant',
      };
}

/// Nom court pour l'affichage : début de l'appareil et numéro.
String shortSegmentName(String fileName) {
  final name = SegmentName.tryParse(fileName);
  if (name == null) return fileName;
  return '${name.deviceId.substring(0, 8)}… n° ${name.seq}';
}