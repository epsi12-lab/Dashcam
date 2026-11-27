import 'package:dashcam_core/dashcam_core.dart';
import 'package:flutter/material.dart';

import 'palette.dart';

/// Libellé, couleur et icône de chaque verdict. La couleur n'est jamais
/// la seule information : le libellé et l'icône l'accompagnent toujours.
extension VerdictStyle on Verdict {
  String get label => switch (this) {
    Verdict.authentic => 'Authentique',
    Verdict.modified => 'Modifié',
    Verdict.inconsistent => 'Incohérent',
    Verdict.unknown => 'Inconnu',
  };

  /// Couleur du texte et de l'icône, lisible sur [background].
  Color get color => switch (this) {
    Verdict.authentic => Palette.okFg,
    Verdict.modified => Palette.errorFg,
    Verdict.inconsistent => Palette.warnFg,
    Verdict.unknown => Palette.neutralFg,
  };

  /// Fond de l'étiquette du verdict.
  Color get background => switch (this) {
    Verdict.authentic => Palette.okBg,
    Verdict.modified => Palette.errorBg,
    Verdict.inconsistent => Palette.warnBg,
    Verdict.unknown => Palette.neutralBg,
  };

  /// Repère coloré des compteurs.
  Color get accent => switch (this) {
    Verdict.authentic => const Color(0xFF1E7A46),
    Verdict.modified => const Color(0xFFC0392B),
    Verdict.inconsistent => const Color(0xFFB45309),
    Verdict.unknown => const Color(0xFF7A8784),
  };

  IconData get icon => switch (this) {
    Verdict.authentic => Icons.check,
    Verdict.modified => Icons.close,
    Verdict.inconsistent => Icons.priority_high,
    Verdict.unknown => Icons.question_mark,
  };
}

extension AlertStyle on Alert {
  String get label => switch (this) {
    Alert.lateDelivery => 'Envoi tardif',
    Alert.missingPrevious => 'Segment précédent manquant',
  };
}

/// Nom court pour l'affichage : début de l'identifiant de l'appareil et
/// numéro du segment.
String shortSegmentName(String fileName) {
  final name = SegmentName.tryParse(fileName);
  if (name == null) return fileName;
  return '${name.deviceId.substring(0, 8)}… n° ${name.seq}';
}
