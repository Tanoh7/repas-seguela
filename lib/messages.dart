import 'data.dart';

/// Message 1 : commande au restaurateur et au comptable (format habituel).
String orderMessage(Order o) {
  final t = o.totals;
  final head = o.isRectified
      ? 'Bonjour, RECTIFICATIF de la commande du ${dmy(o.date)} (annule et remplace le message précédent) :'
      : 'Bonjour, Commande du ${dmy(o.date)} :';
  return '$head\n\n'
      'Service sur place : ${t.place} plats\n\n'
      'Plats dans bol : ${t.pit} plats (Au pit)\n\n'
      'Total jour : ${t.day}\n\n'
      'Nuit : ${t.night}\n\n'
      'Commande faite par : ${o.author}';
}

String _list(Order o, bool pit, bool night) {
  final rows = o.lines
      .where((l) => l.isPit == pit)
      .map((l) => MapEntry(l.name, night ? l.foodNight : l.foodDay))
      .where((e) => e.value > 0)
      .map((e) => '- ${e.key} : ${e.value}')
      .toList();
  return rows.isEmpty ? '- (aucun)' : rows.join('\n');
}

/// Message 2 : répartition par département pour l'équipe de gestion et de partage.
String sharingMessage(Order o) {
  final t = o.totals;
  return '*RÉPARTITION DES REPAS – ${dmy(o.date)}*${o.isRectified ? ' (rectifiée)' : ''}\n\n'
      '*JOUR – SUR PLACE : ${t.place}*\n${_list(o, false, false)}\n\n'
      '*JOUR – AU PIT (bols) : ${t.pit}*\n${_list(o, true, false)}\n\n'
      '*NUIT – SUR PLACE : ${t.nightPlace}*\n${_list(o, false, true)}\n\n'
      '*NUIT – AU PIT : ${t.nightPit}*\n${_list(o, true, true)}\n\n'
      'Total jour : ${t.day} | Nuit : ${t.night}\n'
      'Établi par : ${o.author}';
}

Uri whatsappUri(String phone, String text) {
  final n = phone.replaceAll(RegExp(r'\D'), '');
  return Uri.parse('https://wa.me/$n?text=${Uri.encodeComponent(text)}');
}
