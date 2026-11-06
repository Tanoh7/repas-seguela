import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// Utilitaires de dates (format interne AAAA-MM-JJ)
// ---------------------------------------------------------------------------
String two(int n) => n.toString().padLeft(2, '0');
String isoOf(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
String todayIso() => isoOf(DateTime.now());
DateTime parseIso(String s) {
  final p = s.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}
String addDays(String iso, int k) {
  final d = parseIso(iso);
  return isoOf(DateTime(d.year, d.month, d.day + k));
}
String dmy(String iso) {
  final p = iso.split('-');
  return '${p[2]}/${p[1]}/${p[0]}';
}
String hm(String? isoTs) {
  if (isoTs == null || isoTs.isEmpty) return '';
  final d = DateTime.tryParse(isoTs)?.toLocal();
  if (d == null) return '';
  return '${two(d.hour)}:${two(d.minute)}';
}
int daysInMonth(String month) {
  final p = month.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]) + 1, 0).day;
}

const monthsFr = ['JANVIER', 'FÉVRIER', 'MARS', 'AVRIL', 'MAI', 'JUIN', 'JUILLET', 'AOÛT', 'SEPTEMBRE', 'OCTOBRE', 'NOVEMBRE', 'DÉCEMBRE'];
const monthsEn = ['JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE', 'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER'];
String monthLabel(String month) {
  final p = month.split('-');
  return '${monthsFr[int.parse(p[1]) - 1]} ${p[0]}';
}
String monthLabelNice(String month) {
  final l = monthLabel(month).toLowerCase();
  return l[0].toUpperCase() + l.substring(1);
}

String fmt(num n) {
  final s = n.round().abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return (n < 0 ? '-' : '') + b.toString();
}

int? _int(dynamic v) => v is num ? v.toInt() : null;

// ---------------------------------------------------------------------------
// Modèles
// ---------------------------------------------------------------------------
class Dept {
  String id;
  String name;
  String zone; // 'place' (sur place) ou 'pit' (au pit, en bols)
  Dept(this.id, this.name, this.zone);
  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'zone': zone};
  factory Dept.fromMap(Map m) => Dept('${m['id']}', '${m['name']}', m['zone'] == 'pit' ? 'pit' : 'place');
}

List<Dept> defaultDepts() => [
      Dept('workshop', 'Workshop', 'place'),
      Dept('genie-civil', 'Génie civil', 'place'),
      Dept('logistique', 'Logistique', 'place'),
      Dept('logistique-civil', 'Logistique civil', 'place'),
      Dept('hse', 'HSE', 'place'),
      Dept('fuel', 'Fuel', 'place'),
      Dept('invites', 'Invités', 'place'),
      Dept('stagiaires', 'Stagiaires', 'place'),
      Dept('production', 'Production', 'pit'),
      Dept('topo', 'Topo', 'pit'),
      Dept('fuel-pit', 'Fuel du pit', 'pit'),
      Dept('forage', 'Forage', 'pit'),
      Dept('mms', 'MMS', 'pit'),
      Dept('camps', 'Camps', 'pit'),
      Dept('logistique-pit', 'Logistique pit', 'pit'),
      Dept('drissasso', 'Drissasso', 'pit'),
    ];

class AppSettings {
  int price;
  String deadline;
  String phoneResto, phoneCompta, phonePartage;
  List<Dept> depts;
  AppSettings({required this.price, required this.deadline, required this.phoneResto, required this.phoneCompta, required this.phonePartage, required this.depts});
  factory AppSettings.defaults() => AppSettings(price: 2000, deadline: '08:20', phoneResto: '', phoneCompta: '', phonePartage: '', depts: defaultDepts());
  factory AppSettings.fromMap(Map<String, dynamic> m) {
    final ph = (m['phones'] is Map) ? m['phones'] as Map : {};
    final d = (m['depts'] is List) ? (m['depts'] as List).whereType<Map>().map(Dept.fromMap).toList() : defaultDepts();
    return AppSettings(
      price: _int(m['price']) ?? 2000,
      deadline: (m['deadline'] is String && (m['deadline'] as String).contains(':')) ? m['deadline'] : '08:20',
      phoneResto: '${ph['resto'] ?? ''}',
      phoneCompta: '${ph['compta'] ?? ''}',
      phonePartage: '${ph['partage'] ?? ''}',
      depts: d.isEmpty ? defaultDepts() : d,
    );
  }
  Map<String, dynamic> toMap() => {
        'price': price,
        'deadline': deadline,
        'phones': {'resto': phoneResto, 'compta': phoneCompta, 'partage': phonePartage},
        'depts': depts.map((e) => e.toMap()).toList(),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      };
}

class Line {
  String id, name, zone;
  int? pj, fj, pn, fn; // présence / plats, jour / nuit (plats null = identique à la présence)
  Line(this.id, this.name, this.zone, {this.pj, this.fj, this.pn, this.fn});
  int get foodDay => fj ?? pj ?? 0;
  int get foodNight => fn ?? pn ?? 0;
  bool get isPit => zone == 'pit';
  bool get hasValues => pj != null || fj != null || pn != null || fn != null;
  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'zone': zone, 'pj': pj, 'fj': fj, 'pn': pn, 'fn': fn};
  factory Line.fromMap(Map m) => Line('${m['id']}', '${m['name']}', m['zone'] == 'pit' ? 'pit' : 'place',
      pj: _int(m['pj']), fj: _int(m['fj']), pn: _int(m['pn']), fn: _int(m['fn']));
  factory Line.empty(Dept d) => Line(d.id, d.name, d.zone);
}

class Totals {
  int place = 0, pit = 0, night = 0, nightPlace = 0, nightPit = 0;
  int get day => place + pit;
  int get total => day + night;
}

class Order {
  String date;
  String status; // 'draft' ou 'sent'
  String author;
  String? authorUid;
  String? sentAt;
  int price;
  List<Line> lines;
  List<Map<String, dynamic>> revisions;
  String? createdAt;
  String? source;
  Order({required this.date, this.status = 'draft', this.author = '', this.authorUid, this.sentAt, this.price = 2000, required this.lines, List<Map<String, dynamic>>? revisions, this.createdAt, this.source})
      : revisions = revisions ?? [];

  bool get isSent => status == 'sent';
  bool get isRectified => revisions.isNotEmpty;
  String get month => date.substring(0, 7);

  Totals get totals {
    final t = Totals();
    for (final l in lines) {
      if (l.isPit) {
        t.pit += l.foodDay;
        t.nightPit += l.foodNight;
      } else {
        t.place += l.foodDay;
        t.nightPlace += l.foodNight;
      }
      t.night += l.foodNight;
    }
    return t;
  }

  Map<String, dynamic> toMap() => {
        'date': date,
        'month': month,
        'status': status,
        'author': author,
        'authorUid': authorUid,
        'sentAt': sentAt,
        'price': price,
        'lines': lines.map((e) => e.toMap()).toList(),
        'revisions': revisions,
        'createdAt': createdAt,
        'source': source,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      };

  factory Order.fromMap(Map<String, dynamic> m) => Order(
        date: '${m['date']}',
        status: m['status'] == 'sent' ? 'sent' : 'draft',
        author: '${m['author'] ?? ''}',
        authorUid: m['authorUid'] as String?,
        sentAt: m['sentAt'] as String?,
        price: _int(m['price']) ?? 2000,
        lines: (m['lines'] is List) ? (m['lines'] as List).whereType<Map>().map(Line.fromMap).toList() : <Line>[],
        revisions: (m['revisions'] is List) ? (m['revisions'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [],
        createdAt: m['createdAt'] as String?,
        source: m['source'] as String?,
      );

  Order copy() => Order.fromMap(jsonDecode(jsonEncode(toMap())) as Map<String, dynamic>);
  String linesKey() => jsonEncode(lines.map((e) => e.toMap()).toList());
}

class AgentProfile {
  final String uid, name, email, role;
  final bool active;
  AgentProfile({required this.uid, required this.name, required this.email, required this.role, required this.active});
  bool get isAdmin => role == 'admin';
  factory AgentProfile.fromMap(String uid, Map<String, dynamic> m) => AgentProfile(
        uid: uid,
        name: '${m['name'] ?? ''}',
        email: '${m['email'] ?? ''}',
        role: m['role'] == 'admin' ? 'admin' : 'rh',
        active: m['active'] == true,
      );
}

// ---------------------------------------------------------------------------
// Store : données partagées (Firestore) + commande en cours d'édition
// ---------------------------------------------------------------------------
class Store extends ChangeNotifier {
  final FirebaseFirestore db = FirebaseFirestore.instance;
  AgentProfile profile;
  AppSettings settings = AppSettings.defaults();
  Map<String, Order> orders = {};
  bool loaded = false;
  bool pendingSync = false; // des modifications attendent le réseau
  String? error;

  String date = todayIso();
  late Order cur;
  bool dirty = false;
  int rev = 0; // change quand la commande affichée est rechargée (remonte les champs)
  Timer? _saveTimer;
  final List<StreamSubscription> _subs = [];

  Store(this.profile) {
    cur = _newOrder(date);
    _subs.add(db.doc('config/settings').snapshots().listen((s) {
      if (s.exists && s.data() != null) settings = AppSettings.fromMap(s.data()!);
      if (!orders.containsKey(date) && !dirty) _reload(force: true);
      notifyListeners();
    }, onError: (e) {}));
    _subs.add(db.collection('orders').snapshots(includeMetadataChanges: true).listen((snap) {
      final m = <String, Order>{};
      for (final d in snap.docs) {
        try {
          final o = Order.fromMap(d.data());
          if (o.date.length == 10) m[o.date] = o;
        } catch (_) {}
      }
      orders = m;
      pendingSync = snap.metadata.hasPendingWrites;
      if (!snap.metadata.isFromCache) loaded = true;
      error = null;
      if (!dirty) _reload();
      notifyListeners();
    }, onError: (e) {
      error = 'Impossible de charger les commandes. Vérifiez que votre compte est actif.';
      notifyListeners();
    }));
  }

  void updateProfile(AgentProfile p) {
    profile = p;
    notifyListeners();
  }

  Order _newOrder(String d) => Order(
        date: d,
        author: profile.name,
        authorUid: profile.uid,
        price: settings.price,
        lines: settings.depts.map(Line.empty).toList(),
      );

  void _reload({bool force = false}) {
    final o = orders[date];
    Order next;
    if (o != null) {
      next = o.copy();
      if (!next.isSent) {
        final have = next.lines.map((e) => e.id).toSet();
        for (final d in settings.depts) {
          if (!have.contains(d.id)) next.lines.add(Line.empty(d));
        }
      }
    } else {
      next = _newOrder(date);
    }
    final changed = force || next.linesKey() != cur.linesKey() || cur.date != next.date;
    cur = next;
    if (changed) rev++;
  }

  bool get exists => orders.containsKey(date);
  bool get locked => cur.isSent;

  void goDate(String d) {
    flush();
    date = d;
    dirty = false;
    _reload(force: true);
    notifyListeners();
  }

  void edit(void Function(Order o) f) {
    if (locked) return;
    f(cur);
    dirty = true;
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), flush);
  }

  /// Écrit la commande en cours. Firestore garde l'écriture en local et la
  /// synchronise dès que le réseau revient.
  void flush() {
    _saveTimer?.cancel();
    if (!dirty) return;
    dirty = false;
    final o = cur.copy();
    o.createdAt ??= DateTime.now().toUtc().toIso8601String();
    o.author = o.author.isEmpty ? profile.name : o.author;
    db.collection('orders').doc(o.date).set(o.toMap()).catchError((e) {
      error = "Enregistrement refusé : votre compte n'a peut-être plus accès.";
      notifyListeners();
    });
  }

  void confirmSent() {
    cur.status = 'sent';
    cur.sentAt = DateTime.now().toUtc().toIso8601String();
    cur.price = settings.price;
    cur.author = profile.name;
    cur.authorUid = profile.uid;
    dirty = true;
    flush();
    notifyListeners();
  }

  void rectify(String reason) {
    final t = cur.totals;
    cur.revisions.add({
      'at': DateTime.now().toUtc().toIso8601String(),
      'by': profile.name,
      'reason': reason,
      'before': {'place': t.place, 'pit': t.pit, 'day': t.day, 'night': t.night},
    });
    cur.status = 'draft';
    cur.author = profile.name;
    cur.authorUid = profile.uid;
    dirty = true;
    flush();
    rev++;
    notifyListeners();
  }

  /// Reprend les chiffres de la dernière commande avant la date affichée.
  String? copyPrevious() {
    final keys = orders.keys.where((k) => k.compareTo(date) < 0).toList()..sort();
    if (keys.isEmpty) return null;
    final src = orders[keys.last]!;
    final m = {for (final l in src.lines) l.id: l};
    edit((o) {
      for (final l in o.lines) {
        final s = m[l.id];
        if (s != null) {
          l.pj = s.pj;
          l.fj = s.fj;
          l.pn = s.pn;
          l.fn = s.fn;
        }
      }
    });
    rev++;
    notifyListeners();
    return src.date;
  }

  Future<void> saveSettings(AppSettings s) async {
    await db.doc('config/settings').set(s.toMap());
    settings = s;
    if (!locked) {
      final byId = {for (final d in s.depts) d.id: d};
      final pos = {for (var i = 0; i < s.depts.length; i++) s.depts[i].id: i};
      cur.lines = cur.lines.where((l) => byId.containsKey(l.id) || l.hasValues).map((l) {
        final d = byId[l.id];
        if (d != null) {
          l.name = d.name;
          l.zone = d.zone;
        }
        return l;
      }).toList();
      for (final d in s.depts) {
        if (!cur.lines.any((l) => l.id == d.id)) cur.lines.add(Line.empty(d));
      }
      cur.lines.sort((a, b) => (pos[a.id] ?? 999).compareTo(pos[b.id] ?? 999));
      if (exists) {
        dirty = true;
        flush();
      }
      rev++;
    }
    notifyListeners();
  }

  List<Order> ordersOf(String month) {
    final l = orders.values.where((o) => o.month == month).toList();
    l.sort((a, b) => a.date.compareTo(b.date));
    return l;
  }

  List<String> monthsAvailable() {
    final s = <String>{todayIso().substring(0, 7), date.substring(0, 7)};
    for (final k in orders.keys) {
      s.add(k.substring(0, 7));
    }
    final l = s.toList()..sort();
    return l.reversed.toList();
  }

  /// Import unique de l'historique d'octobre 2026 (fichier Excel d'origine).
  Future<int> importSeed(List<dynamic> list) async {
    var n = 0;
    final batch = db.batch();
    for (final e in list) {
      final m = Map<String, dynamic>.from(e as Map);
      final d = '${m['date']}';
      if (orders.containsKey(d)) continue;
      batch.set(db.collection('orders').doc(d), m);
      n++;
    }
    if (n > 0) await batch.commit();
    return n;
  }

  @override
  void dispose() {
    flush();
    _saveTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
