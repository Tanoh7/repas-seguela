import 'package:excel/excel.dart' as xl;

import 'data.dart';

// Rapport mensuel — reprend le modèle « DSCI FOOD QUANTITY RECORD SEGUELA ».
// Toutes les cellules contiennent des valeurs (et non des formules) pour un
// affichage correct sur téléphone comme sur ordinateur.

const _green = '#8CF7A7', _blue = '#A3DBFF', _red = '#FF7474', _ochre = '#FCE9C4', _grey = '#F2F2F2';

xl.CellStyle _st({bool bold = false, int size = 12, String color = '#000000', String? bg, bool center = true, bool wrap = false, bool italic = false}) {
  final b = xl.Border(borderStyle: xl.BorderStyle.Thin);
  return xl.CellStyle(
    bold: bold,
    italic: italic,
    fontSize: size,
    fontColorHex: xl.ExcelColor.fromHexString(color),
    backgroundColorHex: bg == null ? xl.ExcelColor.none : xl.ExcelColor.fromHexString(bg),
    horizontalAlign: center ? xl.HorizontalAlign.Center : xl.HorizontalAlign.Left,
    verticalAlign: xl.VerticalAlign.Center,
    textWrapping: wrap ? xl.TextWrapping.WrapText : xl.TextWrapping.Clip,
    leftBorder: b,
    rightBorder: b,
    topBorder: b,
    bottomBorder: b,
  );
}

xl.CellIndex _ix(int c, int r) => xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r);

void _put(xl.Sheet s, int c, int r, Object? v, xl.CellStyle style) {
  xl.CellValue? cv;
  if (v == null) {
    cv = null;
  } else if (v is int) {
    cv = xl.IntCellValue(v);
  } else if (v is DateTime) {
    cv = xl.DateCellValue(year: v.year, month: v.month, day: v.day);
  } else {
    cv = xl.TextCellValue('$v');
  }
  s.updateCell(_ix(c, r), cv, cellStyle: style);
}

void _merge(xl.Sheet s, int c1, int r1, int c2, int r2, Object? v, xl.CellStyle style) {
  if (c1 != c2 || r1 != r2) s.merge(_ix(c1, r1), _ix(c2, r2));
  _put(s, c1, r1, v, style);
  for (var c = c1; c <= c2; c++) {
    for (var r = r1; r <= r2; r++) {
      if (c != c1 || r != r1) s.updateCell(_ix(c, r), null, cellStyle: style);
    }
  }
}

void _widths(xl.Sheet s, List<double> w) {
  for (var i = 0; i < w.length; i++) {
    s.setColumnWidth(i, w[i]);
  }
}

void _header(xl.Sheet s, int r, List<String> labels) {
  for (var i = 0; i < labels.length; i++) {
    _put(s, i, r, labels[i], _st(bold: true, size: 11, bg: _blue, wrap: true));
  }
  s.setRowHeight(r, 32);
}

void _title(xl.Sheet s, int lastCol, String text) {
  _merge(s, 0, 0, lastCol, 0, text, _st(bold: true, size: 15, color: '#FF0000', bg: _green));
  s.setRowHeight(0, 24);
}

/// Feuille journalière — copie du modèle habituel.
void _daySheet(xl.Excel x, Order o) {
  final p = o.date.split('-');
  final s = x['${p[2]}-${p[1]}-${p[0]}'];
  _widths(s, [12, 22, 14, 9, 12, 16, 9, 13, 10]);
  final t = o.totals;
  _merge(s, 0, 0, 8, 0, 'DSCI FOOD QUANTITY RECORD SEGUELA', _st(bold: true, size: 16, color: '#FF0000', bg: _green));
  s.setRowHeight(0, 22);
  _header(s, 1, ['DATE', 'FONCTION', 'PRESENCE DAY', 'FOOD', 'TOTAL DAY', 'PRESENCE NIGHT', 'FOOD', 'TOTAL NIGHT', 'TOTAL']);
  const first = 2;
  final last = o.lines.isEmpty ? first : first + o.lines.length - 1;
  for (var i = 0; i < o.lines.length; i++) {
    final l = o.lines[i], r = first + i;
    final cell = _st(size: 14);
    _put(s, 1, r, l.name.toUpperCase(), _st(size: 14, center: false, bg: l.isPit ? _ochre : null));
    // La commande fait office de présence : PRESENCE = plats commandés.
    final hasDay = l.fj != null || l.pj != null, hasNight = l.fn != null || l.pn != null;
    _put(s, 2, r, hasDay ? l.foodDay : null, cell);
    _put(s, 3, r, hasDay ? l.foodDay : null, cell);
    _put(s, 5, r, hasNight ? l.foodNight : null, cell);
    _put(s, 6, r, hasNight ? l.foodNight : null, cell);
    s.setRowHeight(r, 20);
  }
  _merge(s, 0, first, 0, last, parseIso(o.date), _st(bold: true, size: 12, bg: _blue));
  _merge(s, 4, first, 4, last, t.day, _st(bold: true, size: 36));
  _merge(s, 7, first, 7, last, t.night, _st(bold: true, size: 36));
  _merge(s, 8, first, 8, last, t.total, _st(bold: true, size: 28, bg: _red));
  s.updateCell(_ix(1, last + 2),
      xl.TextCellValue('Sur place : ${t.place}   |   Bols (pit) : ${t.pit}   |   Commande faite par : ${o.author.isEmpty ? '—' : o.author}${o.sentAt != null ? '   |   Envoyée à ${hm(o.sentAt)}' : ''}'),
      cellStyle: xl.CellStyle(italic: true, fontSize: 11, fontColorHex: xl.ExcelColor.fromHexString('#555555')));
}

/// Récapitulatif du mois : une ligne par jour, avec montant.
void _recapSheet(xl.Sheet s, String month, Map<String, Order> byDate, int price) {
  _widths(s, [13, 12, 12, 12, 11, 12, 19, 24, 10, 36]);
  _title(s, 9, 'DSCI SÉGUÉLA — RÉCAPITULATIF DES REPAS — ${monthLabel(month)}');
  s.updateCell(_ix(0, 1), xl.TextCellValue('Prix unitaire'), cellStyle: xl.CellStyle(bold: true));
  _put(s, 1, 1, '${fmt(price)} FCFA', _st(bold: true, bg: _ochre));
  _header(s, 3, ['DATE', 'SUR PLACE', 'BOLS (PIT)', 'TOTAL JOUR', 'NUIT', 'TOTAL PLATS', 'MONTANT (FCFA)', 'COMMANDE FAITE PAR', 'ENVOI', 'OBSERVATIONS']);
  final nd = daysInMonth(month);
  final sum = List<int>.filled(6, 0);
  var count = 0;
  for (var d = 1; d <= nd; d++) {
    final iso = '$month-${two(d)}', r = 3 + d;
    final o = byDate[iso];
    final t = o?.totals;
    final obs = <String>[];
    if (o == null) {
      obs.add('Aucune commande enregistrée');
    } else {
      count++;
      if (!o.isSent) obs.add('Brouillon non confirmé');
      for (final rv in o.revisions) {
        obs.add('Rectifiée : ${rv['reason'] ?? ''}');
      }
      final vals = [t!.place, t.pit, t.day, t.night, t.total, t.total * price];
      for (var i = 0; i < 6; i++) {
        sum[i] += vals[i];
      }
    }
    final bg = o == null ? _grey : null;
    final c = _st(size: 11, bg: bg, color: o == null ? '#9A9A9A' : '#000000');
    _put(s, 0, r, parseIso(iso), c);
    _put(s, 1, r, t?.place, c);
    _put(s, 2, r, t?.pit, c);
    _put(s, 3, r, t?.day, c);
    _put(s, 4, r, t?.night, c);
    _put(s, 5, r, t?.total, _st(size: 11, bold: true, bg: o == null ? _grey : '#FFE0E0'));
    _put(s, 6, r, t == null ? null : fmt(t.total * price), c);
    _put(s, 7, r, o?.author ?? '', _st(size: 11, bg: bg, center: false));
    _put(s, 8, r, hm(o?.sentAt), c);
    _put(s, 9, r, obs.join(' · '), _st(size: 11, bg: bg, center: false, wrap: true));
  }
  final tr = 4 + nd;
  final tot = _st(bold: true, bg: _blue);
  _put(s, 0, tr, 'TOTAL', tot);
  for (var i = 0; i < 5; i++) {
    _put(s, i + 1, tr, sum[i], tot);
  }
  _put(s, 6, tr, '${fmt(sum[5])} FCFA', _st(bold: true, bg: _red));
  _merge(s, 7, tr, 9, tr, '$count jour(s) commandé(s) sur $nd', _st(bold: true, bg: _blue, center: false));
  s.setRowHeight(tr, 24);
}

/// Cumul par département (imputation des coûts).
void _deptSheet(xl.Excel x, String month, List<Order> list, int price) {
  final s = x['PAR DÉPARTEMENT'];
  _widths(s, [24, 16, 13, 13, 14, 20]);
  _title(s, 5, 'CUMUL PAR DÉPARTEMENT — ${monthLabel(month)}');
  _header(s, 2, ['DÉPARTEMENT', 'ZONE', 'PLATS JOUR', 'PLATS NUIT', 'TOTAL PLATS', 'MONTANT (FCFA)']);
  final agg = <String, List<dynamic>>{}; // id -> [nom, zone, jour, nuit]
  for (final o in list) {
    for (final l in o.lines) {
      final a = agg.putIfAbsent(l.id, () => [l.name, l.zone, 0, 0]);
      a[0] = l.name;
      a[1] = l.zone;
      a[2] += l.foodDay;
      a[3] += l.foodNight;
    }
  }
  final ids = agg.keys.where((id) => (agg[id]![2] as int) + (agg[id]![3] as int) > 0).toList()
    ..sort((a, b) => (agg[a]![1] == 'pit' ? 1 : 0).compareTo(agg[b]![1] == 'pit' ? 1 : 0));
  var r = 3;
  final sum = List<int>.filled(4, 0);
  for (final id in ids) {
    final a = agg[id]!;
    final pit = a[1] == 'pit';
    final total = (a[2] as int) + (a[3] as int);
    final vals = [a[2] as int, a[3] as int, total, total * price];
    for (var i = 0; i < 4; i++) {
      sum[i] += vals[i];
    }
    _put(s, 0, r, '${a[0]}'.toUpperCase(), _st(size: 11, center: false));
    _put(s, 1, r, pit ? 'Au pit (bols)' : 'Sur place', _st(size: 11, center: false, bg: pit ? _ochre : null));
    for (var i = 0; i < 3; i++) {
      _put(s, i + 2, r, vals[i], _st(size: 11, bold: i == 2));
    }
    _put(s, 5, r, fmt(vals[3]), _st(size: 11));
    r++;
  }
  final tot = _st(bold: true, bg: _blue);
  _put(s, 0, r, 'TOTAL', _st(bold: true, bg: _blue, center: false));
  _put(s, 1, r, '', tot);
  for (var i = 0; i < 3; i++) {
    _put(s, i + 2, r, sum[i], tot);
  }
  _put(s, 5, r, '${fmt(sum[3])} FCFA', _st(bold: true, bg: _red));
}

/// Historique de tous les mois enregistrés.
void _historySheet(xl.Excel x, Iterable<Order> all, String upto, int price) {
  final s = x['HISTORIQUE'];
  _widths(s, [18, 14, 14, 14, 14, 20]);
  _title(s, 5, 'HISTORIQUE DES COMMANDES — DSCI SÉGUÉLA');
  _header(s, 2, ['MOIS', 'JOURS COMMANDÉS', 'TOTAL JOUR', 'TOTAL NUIT', 'TOTAL PLATS', 'MONTANT (FCFA)']);
  final m = <String, List<int>>{};
  for (final o in all) {
    if (o.month.compareTo(upto) > 0) continue;
    final t = o.totals;
    final v = m.putIfAbsent(o.month, () => [0, 0, 0, 0, 0]);
    v[0]++;
    v[1] += t.day;
    v[2] += t.night;
    v[3] += t.total;
    v[4] += t.total * o.price;
  }
  final keys = m.keys.toList()..sort();
  var r = 3;
  final sum = List<int>.filled(5, 0);
  for (final k in keys) {
    final v = m[k]!, cur = k == upto;
    _put(s, 0, r, monthLabel(k), _st(size: 11, bold: cur, center: false, bg: cur ? _ochre : null));
    for (var i = 0; i < 4; i++) {
      _put(s, i + 1, r, v[i], _st(size: 11, bold: cur, bg: cur ? _ochre : null));
    }
    _put(s, 5, r, fmt(v[4]), _st(size: 11, bold: cur, bg: cur ? _ochre : null));
    for (var i = 0; i < 5; i++) {
      sum[i] += v[i];
    }
    r++;
  }
  final tot = _st(bold: true, bg: _blue);
  _put(s, 0, r, 'TOTAL', _st(bold: true, bg: _blue, center: false));
  for (var i = 0; i < 4; i++) {
    _put(s, i + 1, r, sum[i], tot);
  }
  _put(s, 5, r, '${fmt(sum[4])} FCFA', tot);
}

String reportFileName(String month) {
  final p = month.split('-');
  return 'DSCI_SEGUELA_FOOD_RECORD_${monthsEn[int.parse(p[1]) - 1]}_${p[0]}.xlsx';
}

List<int> buildReport({required String month, required Map<String, Order> orders, required int price}) {
  final list = orders.values.where((o) => o.month == month).toList()..sort((a, b) => a.date.compareTo(b.date));
  final byDate = {for (final o in list) o.date: o};
  final x = xl.Excel.createExcel();
  final recapName = 'RÉCAP ${monthLabel(month).split(' ').first}';
  final def = x.getDefaultSheet() ?? 'Sheet1';
  x.rename(def, recapName);
  _recapSheet(x[recapName], month, byDate, price);
  _deptSheet(x, month, list, price);
  _historySheet(x, orders.values, month, price);
  for (final o in list) {
    _daySheet(x, o);
  }
  x.setDefaultSheet(recapName);
  return x.encode() ?? <int>[];
}
