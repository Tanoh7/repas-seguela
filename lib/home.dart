import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data.dart';
import 'feedback.dart';
import 'messages.dart';
import 'report.dart';
import 'theme.dart';

void snack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

Widget notice(String text, {Color bg = K.warnSoft, Color fg = K.warn, IconData icon = Icons.info_outline, Widget? action}) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: fg, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text, style: TextStyle(color: fg, fontSize: 14, height: 1.3)),
            if (action != null) action,
          ]),
        ),
      ]),
    );

Widget pill(String text, Color bg, Color fg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(text.toUpperCase(), style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .5)),
    );

Widget statusPill(Order? o) {
  if (o == null) return pill('Aucune', K.sunk, K.muted);
  if (o.isSent) return o.isRectified ? pill('Rectifiée', K.amberSoft, K.amber) : pill('Envoyée', K.greenSoft, K.green);
  return o.isRectified ? pill('Rectif. en cours', K.amberSoft, K.amber) : pill('Brouillon', K.warnSoft, K.warn);
}

/// Pastille « OK » verte des départements validés.
class OkBadge extends StatelessWidget {
  final bool ok;
  final int index;
  const OkBadge({super.key, required this.ok, required this.index});
  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
        width: 44,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ok ? K.greenBright : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: ok ? K.greenBright : K.line, width: 1.5),
        ),
        child: ok
            ? const Text('OK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: .5))
            : Text('$index', style: const TextStyle(color: K.muted, fontWeight: FontWeight.w700)),
      );
}

class SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const SectionCard({super.key, required this.child, this.padding = const EdgeInsets.all(14)});
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: K.line), borderRadius: BorderRadius.circular(14)),
        child: child,
      );
}

/// Photo de profil ronde (ou initiale si pas de photo).
class Avatar extends StatelessWidget {
  final PublicProfile? profile;
  final String fallbackName;
  final double size;
  const Avatar({super.key, required this.profile, this.fallbackName = '', this.size = 40});
  @override
  Widget build(BuildContext context) {
    final bytes = profile?.photoBytes;
    final name = (profile?.name.isNotEmpty ?? false) ? profile!.name : fallbackName;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: K.redSoft,
        border: Border.all(color: Colors.white, width: size > 50 ? 3 : 1.5),
        boxShadow: size > 50 ? const [BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 2))] : null,
        image: bytes == null ? null : DecorationImage(image: MemoryImage(bytes), fit: BoxFit.cover),
      ),
      alignment: Alignment.center,
      child: bytes != null
          ? null
          : Text(name.isEmpty ? '?' : name.trim()[0].toUpperCase(), style: TextStyle(color: K.red, fontWeight: FontWeight.w900, fontSize: size * .42)),
    );
  }
}

// ===========================================================================
class HomeScreen extends StatefulWidget {
  final Store store;
  const HomeScreen({super.key, required this.store});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int tab = 0;
  Timer? clock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) widget.store.flush();
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    clock?.cancel();
    super.dispose();
  }

  Future<void> openEnvoi(Store s) async {
    s.flush();
    final r = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => EnvoiPage(store: s)));
    if (!mounted) return;
    if (r == 'done') go(0);
    if (r == 'edit') go(1);
  }

  void go(int i) {
    widget.store.flush();
    if (i != tab) HapticFeedback.selectionClick();
    setState(() => tab = i);
  }

  Widget deadlineChip(Store s) {
    String text;
    Color bg = K.sunk, fg = K.ink;
    IconData icon = Icons.schedule;
    if (s.cur.isSent) {
      text = 'Envoyée ${hm(s.cur.sentAt)}'.trim();
      bg = K.greenSoft;
      fg = K.green;
      icon = Icons.check_circle;
    } else if (s.date != todayIso()) {
      text = dmy(s.date);
      icon = Icons.event;
    } else {
      final p = s.settings.deadline.split(':');
      final now = DateTime.now();
      final lim = DateTime(now.year, now.month, now.day, int.tryParse(p[0]) ?? 8, int.tryParse(p.length > 1 ? p[1] : '20') ?? 20);
      final m = (lim.difference(now).inSeconds / 60).round();
      String d(int x) => x >= 60 ? '${x ~/ 60} h ${two(x % 60)}' : '$x min';
      if (m >= 0) {
        text = '${s.settings.deadline} · ${d(m)}';
        if (m <= 30) {
          bg = K.redSoft;
          fg = K.red;
        }
      } else {
        text = 'Retard ${d(-m)}';
        bg = K.red;
        fg = Colors.white;
        icon = Icons.warning_amber_rounded;
      }
    }
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: fg),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 13)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          titleSpacing: 12,
          shape: const Border(bottom: BorderSide(color: K.red, width: 3)),
          title: Row(children: [
            Image.asset('assets/logo_mark.png', width: 34, height: 34, filterQuality: FilterQuality.high),
            const SizedBox(width: 10),
            const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Repas Séguéla', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19, color: K.ink)),
              Text('DE SIMONE C.I. · SÉGUÉLA', style: TextStyle(fontSize: 10.5, color: K.muted, letterSpacing: .8, fontWeight: FontWeight.w600)),
            ]),
          ]),
          actions: [Center(child: deadlineChip(s))],
        ),
        body: Column(children: [
          if (s.error != null) Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: notice(s.error!, bg: K.redSoft, fg: K.red, icon: Icons.error_outline)),
          if (s.pendingSync)
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: notice('Hors connexion : tout est gardé sur le téléphone et sera envoyé dès que le réseau revient.', icon: Icons.cloud_off)),
          Expanded(
            child: IndexedStack(index: tab, children: [
              AccueilTab(store: s, onOrder: () {
                if (s.date != todayIso()) s.goDate(todayIso());
                go(1);
              }),
              CommandeTab(key: ValueKey('cmd-${s.closeSignal}'), store: s, onSend: () => openEnvoi(s)),
              HistoriqueTab(store: s, onOpen: (d) {
                s.goDate(d);
                go(1);
              }),
              RapportTab(store: s),
              ReglagesTab(store: s),
            ]),
          ),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: go,
          height: 66,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Accueil'),
            NavigationDestination(icon: Icon(Icons.restaurant_menu_outlined), selectedIcon: Icon(Icons.restaurant_menu), label: 'Commande'),
            NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Historique'),
            NavigationDestination(icon: Icon(Icons.description_outlined), selectedIcon: Icon(Icons.description), label: 'Rapport'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Réglages'),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// COMMANDE
// ===========================================================================
class CommandeTab extends StatefulWidget {
  final Store store;
  final VoidCallback onSend;
  const CommandeTab({super.key, required this.store, required this.onSend});
  @override
  State<CommandeTab> createState() => _CommandeTabState();
}

class _CommandeTabState extends State<CommandeTab> {
  String? openId; // département ouvert
  late bool placeOpen = !widget.store.locked, pitOpen = !widget.store.locked;
  final Map<String, GlobalKey> keys = {};
  String? lastDate;

  GlobalKey keyOf(String id) => keys.putIfAbsent(id, () => GlobalKey());

  Order? previousOrder() {
    final s = widget.store;
    final k = s.orders.keys.where((x) => x.compareTo(s.date) < 0).toList()..sort();
    return k.isEmpty ? null : s.orders[k.last];
  }

  Future<void> pickDate() async {
    final s = widget.store;
    final d = await showDatePicker(
      context: context,
      initialDate: parseIso(s.date),
      firstDate: DateTime(2025, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (d != null) {
      HapticFeedback.selectionClick();
      s.goDate(isoOf(d));
    }
  }

  Future<void> copyPrev() async {
    final s = widget.store;
    if (s.cur.lines.any((l) => l.hasValues)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Reprendre la veille ?'),
          content: const Text('Les nombres déjà saisis seront remplacés par ceux de la dernière commande. Chaque département devra être revalidé.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
            FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)), onPressed: () => Navigator.pop(c, true), child: const Text('Remplacer')),
          ],
        ),
      );
      if (ok != true) return;
    }
    final d = s.copyPrevious();
    if (!mounted) return;
    if (d == null) {
      Fx.error();
      snack(context, 'Aucune commande précédente à reprendre.');
    } else {
      Fx.tick();
      final first = [...s.cur.lines.where((l) => !l.isPit), ...s.cur.lines.where((l) => l.isPit)];
      setState(() => openId = first.isEmpty ? null : first.first.id);
      snack(context, 'Nombres repris du ${dmy(d)}. Vérifiez et validez chaque département.');
    }
  }

  void validate(Line l) {
    final s = widget.store;
    final next = s.validate(l.id);
    Fx.ok();
    setState(() => openId = next);
    if (next != null) {
      final nl = s.cur.lines.firstWhere((e) => e.id == next);
      setState(() {
        if (nl.isPit) {
          pitOpen = true;
        } else {
          placeOpen = true;
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = keys[next]?.currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), alignment: 0.15, curve: Curves.easeOut);
      });
    } else if (s.cur.allValidated) {
      setState(() {
        placeOpen = false;
        pitOpen = false;
      });
      Timer(const Duration(milliseconds: 250), () {
        if (mounted) snack(context, 'Tous les départements sont validés. Vous pouvez préparer les messages.');
      });
    }
  }

  Widget section(Store s, bool pit) {
    final rows = s.cur.lines.where((l) => l.isPit == pit).toList();
    final ok = rows.where((l) => l.ok).length;
    final day = rows.fold<int>(0, (a, l) => a + l.foodDay), night = rows.fold<int>(0, (a, l) => a + l.foodNight);
    final open = pit ? pitOpen : placeOpen;
    final accent = pit ? K.amber : K.anthracite;
    final prev = previousOrder();
    final prevMap = prev == null ? <String, Line>{} : {for (final l in prev.lines) l.id: l};
    var idx = pit ? s.cur.lines.where((l) => !l.isPit).length : 0;
    return Container(
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: K.line), borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() {
              if (pit) {
                pitOpen = !pitOpen;
              } else {
                placeOpen = !placeOpen;
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: accent, width: 5))),
            child: Row(children: [
              Icon(pit ? Icons.ramen_dining : Icons.restaurant, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(pit ? 'Au pit · plats en bol' : 'Sur place', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  Text('$ok / ${rows.length} validés  ·  Jour $day  ·  Nuit $night', style: const TextStyle(color: K.muted, fontSize: 13)),
                ]),
              ),
              if (ok == rows.length && rows.isNotEmpty) const Icon(Icons.check_circle, color: K.greenBright),
              Icon(open ? Icons.expand_less : Icons.expand_more, color: K.muted, size: 28),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: !open
              ? const SizedBox(width: double.infinity)
              : Column(children: [
                  for (final l in rows)
                    DeptTile(
                      key: keyOf(l.id),
                      store: s,
                      line: l,
                      index: ++idx,
                      open: openId == l.id && !s.locked,
                      previous: prevMap[l.id],
                      onTap: s.locked
                          ? null
                          : () {
                              HapticFeedback.selectionClick();
                              setState(() => openId = openId == l.id ? null : l.id);
                            },
                      onValidate: () => validate(l),
                    ),
                ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    if (lastDate != s.date) {
      if (lastDate != null) {
        placeOpen = !s.locked;
        pitOpen = !s.locked;
      }
      lastDate = s.date;
      openId = null;
    }
    final o = s.cur, t = o.totals;
    final n = o.lines.length, v = o.validatedCount;
    Widget status;
    if (o.isSent) {
      status = pill('Envoyée${o.sentAt != null ? ' · ${hm(o.sentAt)}' : ''}', K.greenSoft, K.green);
    } else if (s.exists || s.dirty) {
      status = o.isRectified ? pill('Rectification', K.amberSoft, K.amber) : pill('Brouillon', K.warnSoft, K.warn);
    } else {
      status = pill('Nouvelle', K.sunk, K.muted);
    }
    final remaining = n - v;
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 20), children: [
          // Date
          Row(children: [
            _RoundBtn(icon: Icons.chevron_left, onTap: () => s.goDate(addDays(s.date, -1)), tooltip: 'Jour précédent'),
            const SizedBox(width: 8),
            Expanded(
              child: Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: K.line)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: pickDate,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(children: [
                      Text(s.date == todayIso() ? "AUJOURD'HUI" : 'COMMANDE DU', style: const TextStyle(fontSize: 11, color: K.muted, fontWeight: FontWeight.w800, letterSpacing: .8)),
                      Text(dmy(s.date), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _RoundBtn(icon: Icons.chevron_right, onTap: () => s.goDate(addDays(s.date, 1)), tooltip: 'Jour suivant'),
          ]),
          const SizedBox(height: 12),
          // Progression
          SectionCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                    child: Text(o.isSent ? 'Commande envoyée' : 'Validation : $v / $n départements',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                status,
              ]),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: o.isSent ? 1 : (n == 0 ? 0 : v / n),
                  minHeight: 10,
                  backgroundColor: K.sunk,
                  color: K.greenBright,
                ),
              ),
              if (!s.locked) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: K.red, padding: EdgeInsets.zero),
                    onPressed: copyPrev,
                    icon: const Icon(Icons.history, size: 20),
                    label: const Text('Reprendre les nombres de la veille', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
              if (s.locked)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text('Envoyée${o.author.isNotEmpty ? ' par ${o.author}' : ''}. Pour corriger : onglet Envoi › Rectifier.',
                      style: const TextStyle(color: K.muted, fontSize: 13)),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          section(s, false),
          const SizedBox(height: 12),
          section(s, true),
          const SizedBox(height: 12),
          Text('Commande faite par : ${o.isSent ? o.author : s.profile.name}', style: const TextStyle(color: K.muted)),
        ]),
      ),
      // Totaux + action
      Container(
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: K.line))),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(children: [
          Row(children: [
            _Total('Sur place', t.place),
            _Total('Bols pit', t.pit),
            _Total('Total jour', t.day, strong: true),
            _Total('Nuit', t.night, strong: true),
          ]),
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: (o.allValidated || o.isSent) ? K.red : K.muted),
            onPressed: () {
              if (o.allValidated || o.isSent) {
                HapticFeedback.lightImpact();
                widget.onSend();
              } else {
                Fx.error();
                snack(context, 'Validez encore $remaining département(s) avant de préparer les messages.');
              }
            },
            icon: Icon((o.allValidated || o.isSent) ? Icons.send : Icons.lock_outline),
            label: Text((o.allValidated || o.isSent) ? 'Préparer les messages' : 'Encore $remaining à valider'),
          ),
        ]),
      ),
    ]);
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  const _RoundBtn({required this.icon, required this.onTap, required this.tooltip});
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.white,
          shape: const CircleBorder(side: BorderSide(color: K.line)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: SizedBox(width: 50, height: 50, child: Icon(icon, size: 28)),
          ),
        ),
      );
}

class _Total extends StatelessWidget {
  final String label;
  final int value;
  final bool strong;
  const _Total(this.label, this.value, {this.strong = false});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(fmt(value), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: strong ? K.red : K.ink)),
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, color: K.muted, fontWeight: FontWeight.w800)),
        ]),
      );
}

/// Un département : ligne repliée (OK + nombres) ou fiche de saisie ouverte.
class DeptTile extends StatelessWidget {
  final Store store;
  final Line line;
  final int index;
  final bool open;
  final Line? previous;
  final VoidCallback? onTap;
  final VoidCallback onValidate;
  const DeptTile({super.key, required this.store, required this.line, required this.index, required this.open, required this.previous, required this.onTap, required this.onValidate});

  @override
  Widget build(BuildContext context) {
    final l = line;
    final filled = l.fj != null || l.fn != null || l.pj != null || l.pn != null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: open ? const Color(0xFFFFFAFA) : (l.ok ? const Color(0xFFF6FBF2) : Colors.white),
        border: Border(top: const BorderSide(color: K.line), left: BorderSide(color: open ? K.red : Colors.transparent, width: 4)),
      ),
      child: Column(children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(children: [
              OkBadge(ok: l.ok, index: index),
              const SizedBox(width: 12),
              Expanded(child: Text(l.name, style: TextStyle(fontSize: 16, fontWeight: open ? FontWeight.w800 : FontWeight.w600))),
              if (!open)
                filled || l.ok
                    ? Text('J ${l.foodDay}  ·  N ${l.foodNight}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))
                    : const Text('À saisir', style: TextStyle(color: K.muted, fontStyle: FontStyle.italic)),
              if (onTap != null) Icon(open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: K.muted),
            ]),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              DishStepper(
                key: ValueKey('${store.rev}|${store.date}|${l.id}|j'),
                label: 'Jour',
                icon: Icons.wb_sunny_outlined,
                value: l.fj ?? l.pj,
                previous: previous?.foodDay,
                onChanged: (v) => store.setDish(l.id, false, v),
              ),
              const SizedBox(height: 10),
              DishStepper(
                key: ValueKey('${store.rev}|${store.date}|${l.id}|n'),
                label: 'Nuit',
                icon: Icons.nightlight_outlined,
                value: l.fn ?? l.pn,
                previous: previous?.foodNight,
                onChanged: (v) => store.setDish(l.id, true, v),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: K.greenBright),
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  onValidate();
                },
                icon: const Icon(Icons.check_rounded, size: 26),
                label: Text('Valider ${l.name}'),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// Saisie d'un nombre de plats : gros boutons − / + (appui long = ±10) et clavier.
class DishStepper extends StatefulWidget {
  final String label;
  final IconData icon;
  final int? value;
  final int? previous;
  final ValueChanged<int?> onChanged;
  const DishStepper({super.key, required this.label, required this.icon, required this.value, required this.previous, required this.onChanged});
  @override
  State<DishStepper> createState() => _DishStepperState();
}

class _DishStepperState extends State<DishStepper> {
  late final TextEditingController c = TextEditingController(text: widget.value?.toString() ?? '');

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  int get current => int.tryParse(c.text) ?? 0;

  void setValue(int v) {
    v = v.clamp(0, 9999);
    c.text = '$v';
    c.selection = TextSelection.collapsed(offset: c.text.length);
    widget.onChanged(v);
    setState(() {});
  }

  Widget btn(IconData icon, int step) => Material(
        color: step > 0 ? K.red : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: step > 0 ? K.red : K.line, width: 1.5)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            if (step < 0 && current == 0) {
              Fx.error();
              return;
            }
            Fx.tick();
            setValue(current + step);
          },
          onLongPress: () {
            Fx.tick();
            setValue(current + step * 10);
          },
          child: SizedBox(width: 58, height: 54, child: Icon(icon, size: 30, color: step > 0 ? Colors.white : K.ink)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = widget.previous;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(widget.icon, size: 18, color: K.muted),
        const SizedBox(width: 6),
        Text('Plats ${widget.label.toLowerCase()}', style: const TextStyle(fontWeight: FontWeight.w700, color: K.muted)),
        const Spacer(),
        if (p != null)
          InkWell(
            onTap: () {
              Fx.tick();
              setValue(p);
            },
            borderRadius: BorderRadius.circular(99),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: K.sunk, borderRadius: BorderRadius.circular(99)),
              child: Text('Veille : $p', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        btn(Icons.remove, -1),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
            decoration: const InputDecoration(hintText: '0', contentPadding: EdgeInsets.symmetric(vertical: 10)),
            onChanged: (v) => widget.onChanged(v.isEmpty ? null : int.tryParse(v)),
          ),
        ),
        const SizedBox(width: 10),
        btn(Icons.add, 1),
      ]),
    ]);
  }
}

// ===========================================================================
// ENVOI
// ===========================================================================
class EnvoiPage extends StatelessWidget {
  final Store store;
  const EnvoiPage({super.key, required this.store});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) => Scaffold(
          appBar: AppBar(
            title: const Text('Envoi de la commande', style: TextStyle(fontWeight: FontWeight.w800)),
            shape: const Border(bottom: BorderSide(color: K.red, width: 3)),
          ),
          body: EnvoiBody(store: store, onEdit: () => Navigator.of(context).pop('edit'), onDone: () => Navigator.of(context).pop('done')),
        ),
      );
}

class EnvoiBody extends StatelessWidget {
  final Store store;
  final VoidCallback onEdit;
  final VoidCallback onDone;
  const EnvoiBody({super.key, required this.store, required this.onEdit, required this.onDone});

  Future<void> openWa(BuildContext context, String phone, String text) async {
    store.flush();
    HapticFeedback.lightImpact();
    final ok = await launchUrl(whatsappUri(phone, text), mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && context.mounted) {
      Fx.error();
      snack(context, "WhatsApp n'a pas pu s'ouvrir. Utilisez « Copier ».");
    }
  }

  Future<void> copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    Fx.tick();
    if (context.mounted) snack(context, 'Message copié.');
  }

  Future<void> rectify(BuildContext context) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Rectifier la commande du ${dmy(store.cur.date)}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text("La commande repasse en brouillon. Le motif et les anciens totaux restent dans l'historique et le rapport."),
          const SizedBox(height: 12),
          TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: 'Motif', hintText: 'Ex. : 12 travailleurs en plus à la production')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)), onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Rectifier')),
        ],
      ),
    );
    if (reason == null) return;
    if (reason.isEmpty) {
      Fx.error();
      if (context.mounted) snack(context, 'Indiquez le motif de la rectification.');
      return;
    }
    store.rectify(reason);
    Fx.tick();
    onEdit();
    if (context.mounted) snack(context, 'Corrigez les nombres, validez, puis renvoyez le rectificatif.');
  }

  Widget msgCard(String step, String title, String sub, String text, List<Widget> buttons) => SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            CircleAvatar(radius: 14, backgroundColor: K.red, child: Text(step, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                Text(sub, style: const TextStyle(color: K.muted, fontSize: 13)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFE7F5E9), borderRadius: BorderRadius.circular(10)),
            child: SelectableText(text, style: const TextStyle(fontSize: 14.5, height: 1.4)),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: buttons),
        ]),
      );

  Widget waBtn(BuildContext context, String label, String phone, String text) => FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: K.wa, minimumSize: const Size(0, 48)),
        onPressed: () => openWa(context, phone, text),
        icon: const Icon(Icons.chat),
        label: Text(label),
      );

  Widget smallBtn(String label, IconData icon, VoidCallback f) =>
      OutlinedButton.icon(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)), onPressed: f, icon: Icon(icon, size: 18), label: Text(label));

  @override
  Widget build(BuildContext context) {
    final o = store.cur, t = o.totals, st = store.settings;
    final view = o.copy()..author = o.isSent ? o.author : store.profile.name;
    final m1 = orderMessage(view), m2 = sharingMessage(view);
    final ready = o.allValidated || o.isSent;
    return ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 24), children: [
      Text('Envoi du ${dmy(o.date)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      if (!ready) ...[
        notice('Validez encore ${o.lines.length - o.validatedCount} département(s) avant d\'envoyer.',
            icon: Icons.lock_outline, action: TextButton(onPressed: onEdit, child: const Text('Retour à la saisie'))),
        const SizedBox(height: 10),
      ],
      Opacity(
        opacity: ready ? 1 : .45,
        child: IgnorePointer(
          ignoring: !ready,
          child: Column(children: [
            msgCard('1', 'Commande', 'Au restaurateur et au comptable', m1, [
              waBtn(context, 'Restaurateur', st.phoneResto, m1),
              waBtn(context, 'Comptable', st.phoneCompta, m1),
              smallBtn('Copier', Icons.copy, () => copy(context, m1)),
              smallBtn('Partager', Icons.share, () => Share.share(m1)),
            ]),
            const SizedBox(height: 12),
            msgCard('2', 'Répartition par département', "À l'équipe de gestion et de partage", m2, [
              waBtn(context, 'Équipe partage', st.phonePartage, m2),
              smallBtn('Copier', Icons.copy, () => copy(context, m2)),
              smallBtn('Partager', Icons.share, () => Share.share(m2)),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      if (o.isSent) ...[
        notice('Envoi confirmé${o.sentAt != null ? ' à ${hm(o.sentAt)}' : ''}${o.author.isNotEmpty ? ' par ${o.author}' : ''}. La commande est verrouillée.',
            bg: K.greenSoft, fg: K.green, icon: Icons.verified),
        for (final r in o.revisions)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
                'Rectifiée le ${dmy('${r['at']}'.substring(0, 10))} à ${hm('${r['at']}')} par ${r['by'] ?? ''} : ${r['reason'] ?? ''} (avant : jour ${(r['before'] as Map?)?['day'] ?? '?'}, nuit ${(r['before'] as Map?)?['night'] ?? '?'})',
                style: const TextStyle(color: K.muted, fontSize: 13)),
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: K.red, side: const BorderSide(color: K.red)),
          onPressed: () => rectify(context),
          icon: const Icon(Icons.edit),
          label: const Text('Rectifier cette commande'),
        ),
      ] else if (ready) ...[
        const Text("Après l'envoi des deux messages sur WhatsApp, confirmez ici. La commande sera verrouillée et datée.", style: TextStyle(color: K.muted)),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: t.total == 0
              ? null
              : () {
                  store.confirmSent();
                  Fx.success();
                  snack(context, 'Commande confirmée et verrouillée.');
                  onDone();
                },
          icon: const Icon(Icons.check_circle),
          label: const Text("J'ai envoyé la commande"),
        ),
      ],
    ]);
  }
}

// ===========================================================================
// HISTORIQUE
// ===========================================================================
class HistoriqueTab extends StatefulWidget {
  final Store store;
  final ValueChanged<String> onOpen;
  const HistoriqueTab({super.key, required this.store, required this.onOpen});
  @override
  State<HistoriqueTab> createState() => _HistoriqueTabState();
}

class _HistoriqueTabState extends State<HistoriqueTab> {
  String? month;

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final months = s.monthsAvailable();
    final m = (month != null && months.contains(month)) ? month! : months.first;
    final nd = daysInMonth(m);
    var day = 0, night = 0, total = 0;
    final rows = <Widget>[];
    for (var d = 1; d <= nd; d++) {
      final k = '$m-${two(d)}';
      final o = s.orders[k];
      final t = o?.totals;
      if (t != null) {
        day += t.day;
        night += t.night;
        total += t.total;
      }
      rows.add(InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onOpen(k);
        },
        child: Container(
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: K.line))),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(children: [
            SizedBox(width: 92, child: Text(dmy(k), style: TextStyle(fontWeight: FontWeight.w700, color: o == null ? K.muted : K.ink))),
            Expanded(
                child: Text(t == null ? '—' : 'Jour ${t.day} (${t.place} + ${t.pit})  ·  Nuit ${t.night}',
                    style: TextStyle(color: o == null ? K.muted : K.ink, fontSize: 13))),
            if (o != null && o.isSent && o.author.isNotEmpty)
              Padding(padding: const EdgeInsets.only(right: 8), child: Avatar(profile: s.profileOf(o.authorUid), fallbackName: o.author, size: 26)),
            if (t != null) Padding(padding: const EdgeInsets.only(right: 8), child: Text('${t.total}', style: const TextStyle(fontWeight: FontWeight.w900))),
            statusPill(o),
          ]),
        ),
      ));
    }
    return ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 24), children: [
      Row(children: [
        const Expanded(child: Text('Historique', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
        DropdownButton<String>(
          value: m,
          items: [for (final x in months) DropdownMenuItem(value: x, child: Text(monthLabelNice(x)))],
          onChanged: (v) => setState(() => month = v),
        ),
      ]),
      const SizedBox(height: 10),
      SectionCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          ...rows,
          Container(
            color: K.sunk,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(children: [
              const Expanded(child: Text('TOTAL', style: TextStyle(fontWeight: FontWeight.w900))),
              Text('Jour ${fmt(day)} · Nuit ${fmt(night)} · ${fmt(total)} plats', style: const TextStyle(fontWeight: FontWeight.w800)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 8),
      const Text('Touchez une ligne pour ouvrir la commande.', style: TextStyle(color: K.muted, fontSize: 13)),
    ]);
  }
}

// ===========================================================================
// RAPPORT
// ===========================================================================
class RapportTab extends StatefulWidget {
  final Store store;
  const RapportTab({super.key, required this.store});
  @override
  State<RapportTab> createState() => _RapportTabState();
}

class _RapportTabState extends State<RapportTab> {
  String? month;
  bool busy = false;

  Future<void> export(String m) async {
    setState(() => busy = true);
    HapticFeedback.lightImpact();
    try {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final bytes = buildReport(month: m, orders: widget.store.orders, price: widget.store.settings.price);
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/${reportFileName(m)}');
      await f.writeAsBytes(bytes, flush: true);
      Fx.ok();
      await Share.shareXFiles(
        [XFile(f.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
        subject: 'Rapport repas ${monthLabelNice(m)} — DSCI Séguéla',
        text: 'Bonjour, veuillez trouver ci-joint le rapport des commandes de repas de ${monthLabelNice(m).toLowerCase()} (DSCI Séguéla).',
      );
    } catch (e) {
      Fx.error();
      if (mounted) snack(context, "Le rapport n'a pas pu être créé : $e");
    }
    if (mounted) setState(() => busy = false);
  }

  Widget kpi(String label, String value, {bool money = false, String? sub}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: money ? K.red : Colors.white, border: Border.all(color: money ? K.red : K.line), borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: money ? Colors.white70 : K.muted)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: money ? 28 : 26, fontWeight: FontWeight.w900, color: money ? Colors.white : K.ink)),
          if (sub != null) Text(sub, style: TextStyle(fontSize: 12, color: money ? Colors.white70 : K.muted)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final months = s.monthsAvailable();
    final m = (month != null && months.contains(month)) ? month! : months.first;
    final list = s.ordersOf(m), price = s.settings.price, nd = daysInMonth(m);
    var day = 0, night = 0, total = 0;
    final agg = <String, List<dynamic>>{};
    for (final o in list) {
      final t = o.totals;
      day += t.day;
      night += t.night;
      total += t.total;
      for (final l in o.lines) {
        final a = agg.putIfAbsent(l.id, () => [l.name, l.zone, 0, 0]);
        a[2] += l.foodDay;
        a[3] += l.foodNight;
      }
    }
    final today = todayIso();
    var missing = 0;
    for (var d = 1; d <= nd; d++) {
      final k = '$m-${two(d)}';
      if (k.compareTo(today) <= 0 && !s.orders.containsKey(k)) missing++;
    }
    final drafts = list.where((o) => !o.isSent).length;
    final warn = <String>[
      if (missing > 0) '$missing jour(s) passé(s) sans commande enregistrée.',
      if (drafts > 0) '$drafts commande(s) en brouillon, non confirmée(s).',
    ];
    final ids = agg.keys.where((id) => (agg[id]![2] as int) + (agg[id]![3] as int) > 0).toList()
      ..sort((a, b) => (agg[a]![1] == 'pit' ? 1 : 0).compareTo(agg[b]![1] == 'pit' ? 1 : 0));
    return ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 24), children: [
      Row(children: [
        const Expanded(child: Text('Rapport mensuel', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
        DropdownButton<String>(
          value: m,
          items: [for (final x in months) DropdownMenuItem(value: x, child: Text(monthLabelNice(x)))],
          onChanged: (v) => setState(() => month = v),
        ),
      ]),
      const SizedBox(height: 10),
      kpi('Montant du mois', '${fmt(total * price)} FCFA', money: true, sub: '${fmt(total)} plats × ${fmt(price)} FCFA'),
      const SizedBox(height: 10),
      Row(children: [Expanded(child: kpi('Plats jour', fmt(day))), const SizedBox(width: 10), Expanded(child: kpi('Plats nuit', fmt(night)))]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: kpi('Jours commandés', '${list.length} / $nd')),
        const SizedBox(width: 10),
        Expanded(child: kpi('Moyenne / jour', list.isEmpty ? '0' : fmt(total / list.length))),
      ]),
      const SizedBox(height: 10),
      if (warn.isNotEmpty)
        notice(warn.join(' '), icon: Icons.warning_amber_rounded)
      else if (list.isNotEmpty)
        notice('Toutes les commandes du mois sont confirmées.', bg: K.greenSoft, fg: K.green, icon: Icons.verified),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: (list.isEmpty || busy) ? null : () => export(m),
        icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.table_view),
        label: Text(busy ? 'Préparation…' : 'Créer et envoyer le rapport Excel'),
      ),
      const SizedBox(height: 6),
      const Text(
          "Le fichier contient le récapitulatif du mois avec montants, le cumul par département, l'historique de tous les mois, puis une feuille par jour au format habituel. Vous choisissez ensuite l'application d'envoi (e-mail, WhatsApp…).",
          style: TextStyle(color: K.muted, fontSize: 13)),
      const SizedBox(height: 14),
      SectionCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          Container(
            color: K.sunk,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: const Row(children: [
              Expanded(child: Text('DÉPARTEMENT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: K.muted))),
              SizedBox(width: 56, child: Text('JOUR', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: K.muted))),
              SizedBox(width: 52, child: Text('NUIT', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: K.muted))),
              SizedBox(width: 96, child: Text('MONTANT', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: K.muted))),
            ]),
          ),
          if (ids.isEmpty) const Padding(padding: EdgeInsets.all(14), child: Text('Aucune commande ce mois-ci.', style: TextStyle(color: K.muted))),
          for (final id in ids)
            Container(
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: K.line))),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Expanded(child: Text('${agg[id]![0]}${agg[id]![1] == 'pit' ? ' · pit' : ''}')),
                SizedBox(width: 56, child: Text(fmt(agg[id]![2] as int), textAlign: TextAlign.right)),
                SizedBox(width: 52, child: Text(fmt(agg[id]![3] as int), textAlign: TextAlign.right)),
                SizedBox(
                    width: 96,
                    child: Text(fmt(((agg[id]![2] as int) + (agg[id]![3] as int)) * price), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800))),
              ]),
            ),
        ]),
      ),
    ]);
  }
}

// ===========================================================================
// RÉGLAGES
// ===========================================================================
class ReglagesTab extends StatefulWidget {
  final Store store;
  const ReglagesTab({super.key, required this.store});
  @override
  State<ReglagesTab> createState() => _ReglagesTabState();
}

class _ReglagesTabState extends State<ReglagesTab> {
  final price = TextEditingController(), resto = TextEditingController(), compta = TextEditingController(), partage = TextEditingController();
  String deadline = '08:20';
  List<Dept> depts = [];
  List<TextEditingController> names = [];
  bool loadedForm = false, saving = false;

  void loadForm() {
    final st = widget.store.settings;
    price.text = '${st.price}';
    resto.text = st.phoneResto;
    compta.text = st.phoneCompta;
    partage.text = st.phonePartage;
    deadline = st.deadline;
    depts = st.depts.map((d) => Dept(d.id, d.name, d.zone)).toList();
    names = depts.map((d) => TextEditingController(text: d.name)).toList();
    loadedForm = true;
  }

  String slug(String s) {
    const from = 'àâäáãéèêëíìîïóòôöõúùûüçñ';
    const to = 'aaaaaeeeeiiiiooooouuuucn';
    var r = s.toLowerCase();
    for (var i = 0; i < from.length; i++) {
      r = r.replaceAll(from[i], to[i]);
    }
    r = r.replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    return r.isEmpty ? 'd${DateTime.now().millisecondsSinceEpoch}' : r;
  }

  Future<void> save() async {
    final used = <String>{};
    final out = <Dept>[];
    for (var i = 0; i < depts.length; i++) {
      final n = names[i].text.trim();
      if (n.isEmpty) continue;
      var id = depts[i].id.isEmpty ? slug(n) : depts[i].id;
      while (used.contains(id)) {
        id = '$id-2';
      }
      used.add(id);
      out.add(Dept(id, n, depts[i].zone));
    }
    if (out.isEmpty) {
      Fx.error();
      snack(context, 'Gardez au moins un département.');
      return;
    }
    setState(() => saving = true);
    final st = AppSettings(
      price: int.tryParse(price.text.trim()) ?? 2000,
      deadline: deadline,
      phoneResto: resto.text.replaceAll(RegExp(r'\D'), ''),
      phoneCompta: compta.text.replaceAll(RegExp(r'\D'), ''),
      phonePartage: partage.text.replaceAll(RegExp(r'\D'), ''),
      depts: out,
    );
    try {
      await widget.store.saveSettings(st).timeout(const Duration(seconds: 20));
      loadForm();
      Fx.ok();
      if (mounted) snack(context, 'Réglages enregistrés.');
    } on TimeoutException {
      if (mounted) snack(context, 'Réglages gardés sur le téléphone ; ils seront envoyés dès que le réseau revient.');
    } catch (e) {
      Fx.error();
      if (mounted) snack(context, 'Enregistrement impossible : $e');
    }
    if (mounted) setState(() => saving = false);
  }

  Future<void> pickTime() async {
    final p = deadline.split(':');
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: int.tryParse(p[0]) ?? 8, minute: int.tryParse(p[1]) ?? 20));
    if (t != null) setState(() => deadline = '${two(t.hour)}:${two(t.minute)}');
  }

  Future<void> importOctober() async {
    try {
      final raw = await rootBundle.loadString('assets/seed_octobre_2026.json');
      final n = await widget.store.importSeed(jsonDecode(raw) as List<dynamic>).timeout(const Duration(seconds: 30));
      Fx.ok();
      if (mounted) snack(context, n == 0 ? "Octobre 2026 est déjà dans l'historique." : "$n jours d'octobre 2026 importés.");
    } catch (e) {
      Fx.error();
      if (mounted) snack(context, 'Import impossible : $e');
    }
  }

  Future<void> editName() async {
    final c = TextEditingController(text: widget.store.profile.name);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nom et prénom'),
        content: TextField(
            controller: c,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(helperText: 'Apparaît dans « Commande faite par »')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)), onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (v == null || v == widget.store.profile.name) return;
    if (v.length < 3) {
      Fx.error();
      if (mounted) snack(context, 'Saisissez votre nom et prénom.');
      return;
    }
    try {
      await widget.store.updateMyName(v).timeout(const Duration(seconds: 20));
      Fx.ok();
      if (mounted) snack(context, 'Nom modifié.');
    } on TimeoutException {
      if (mounted) snack(context, 'Modification gardée sur le téléphone ; envoyée dès que le réseau revient.');
    } catch (e) {
      Fx.error();
      if (mounted) snack(context, 'Modification impossible : $e');
    }
  }

  Future<void> changePhoto() async {
    final hasPhoto = widget.store.me.photoBytes != null;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera, color: K.red), title: const Text('Prendre une photo'), onTap: () => Navigator.pop(ctx, 'camera')),
          ListTile(leading: const Icon(Icons.photo_library, color: K.red), title: const Text('Choisir dans la galerie'), onTap: () => Navigator.pop(ctx, 'gallery')),
          if (hasPhoto) ListTile(leading: const Icon(Icons.delete_outline, color: K.muted), title: const Text('Retirer la photo'), onTap: () => Navigator.pop(ctx, 'remove')),
        ]),
      ),
    );
    if (choice == null) return;
    try {
      if (choice == 'remove') {
        await widget.store.updateMyPhoto(null).timeout(const Duration(seconds: 20));
      } else {
        final x = await ImagePicker().pickImage(
          source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
          preferredCameraDevice: CameraDevice.front,
          maxWidth: 320,
          maxHeight: 320,
          imageQuality: 70,
        );
        if (x == null) return;
        final bytes = await x.readAsBytes();
        if (bytes.length > 140000) {
          Fx.error();
          if (mounted) snack(context, 'Photo trop lourde. Essayez une autre photo.');
          return;
        }
        await widget.store.updateMyPhoto(bytes).timeout(const Duration(seconds: 20));
      }
      Fx.ok();
      if (mounted) snack(context, choice == 'remove' ? 'Photo retirée.' : 'Photo de profil enregistrée.');
    } on TimeoutException {
      if (mounted) snack(context, 'Photo gardée sur le téléphone ; envoyée dès que le réseau revient.');
    } catch (e) {
      Fx.error();
      if (mounted) snack(context, 'Photo impossible : $e');
    }
  }

  Widget title(String t) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)));

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    if (!loadedForm) loadForm();
    final p = s.profile;
    final hasOct = s.orders.keys.any((k) => k.startsWith('2026-10'));
    return ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 32), children: [
      const Text('Réglages', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      SectionCard(
        child: Row(children: [
          GestureDetector(
            onTap: changePhoto,
            child: Stack(children: [
              Avatar(profile: s.me, fallbackName: p.name, size: 64),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(color: K.red, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                  child: const Icon(Icons.photo_camera, color: Colors.white, size: 14),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              Text('${p.email} · ${p.isAdmin ? 'Administrateur' : 'Agent RH'}', style: const TextStyle(color: K.muted, fontSize: 13)),
              const SizedBox(height: 4),
              Wrap(spacing: 4, children: [
                TextButton.icon(
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), visualDensity: VisualDensity.compact, foregroundColor: K.red),
                  onPressed: editName,
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text('Modifier le nom'),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), visualDensity: VisualDensity.compact, foregroundColor: K.muted),
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  icon: const Icon(Icons.logout, size: 16),
                  label: const Text('Déconnexion'),
                ),
              ]),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      SectionCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.volume_up_outlined),
            title: const Text('Son de validation'),
            value: Fx.sound,
            onChanged: (v) async {
              await Fx.setSound(v);
              if (v) Fx.ok();
              setState(() {});
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.vibration),
            title: const Text('Vibration au toucher'),
            value: Fx.vibrate,
            onChanged: (v) async {
              await Fx.setVibrate(v);
              if (v) Fx.ok();
              setState(() {});
            },
          ),
        ]),
      ),
      const SizedBox(height: 12),
      SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          title('Commande'),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: price,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: "Prix d'un plat (FCFA)"))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(onPressed: pickTime, icon: const Icon(Icons.schedule), label: Text('Limite $deadline'))),
          ]),
          const SizedBox(height: 14),
          const Text('Numéros WhatsApp au format international, sans + ni espaces (ex. 2250700000000). Laissés vides, WhatsApp vous laisse choisir le contact ou le groupe.',
              style: TextStyle(color: K.muted, fontSize: 13)),
          const SizedBox(height: 10),
          TextField(controller: resto, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Restaurateur', prefixIcon: Icon(Icons.storefront))),
          const SizedBox(height: 10),
          TextField(controller: compta, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Comptable', prefixIcon: Icon(Icons.account_balance))),
          const SizedBox(height: 10),
          TextField(controller: partage, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Équipe gestion et partage', prefixIcon: Icon(Icons.groups))),
        ]),
      ),
      const SizedBox(height: 12),
      SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          title('Départements'),
          const Text("L'ordre ici est l'ordre de saisie et des feuilles Excel.", style: TextStyle(color: K.muted, fontSize: 13)),
          const SizedBox(height: 8),
          for (var i = 0; i < depts.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(child: TextField(controller: names[i], decoration: const InputDecoration(hintText: 'Nom'))),
                const SizedBox(width: 6),
                DropdownButton<String>(
                  value: depts[i].zone,
                  items: const [DropdownMenuItem(value: 'place', child: Text('Sur place')), DropdownMenuItem(value: 'pit', child: Text('Au pit'))],
                  onChanged: (v) => setState(() => depts[i].zone = v ?? 'place'),
                ),
                IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Monter',
                    onPressed: i == 0
                        ? null
                        : () => setState(() {
                              depts.insert(i - 1, depts.removeAt(i));
                              names.insert(i - 1, names.removeAt(i));
                            }),
                    icon: const Icon(Icons.arrow_upward)),
                IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Retirer',
                    onPressed: () => setState(() {
                          depts.removeAt(i);
                          names.removeAt(i);
                        }),
                    icon: const Icon(Icons.close, color: K.red)),
              ]),
            ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
              onPressed: () => setState(() {
                    depts.add(Dept('', '', 'place'));
                    names.add(TextEditingController());
                  }),
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un département')),
        ]),
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: saving ? null : save,
        child: saving ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Enregistrer les réglages'),
      ),
      TextButton(onPressed: () => setState(loadForm), child: const Text('Annuler les modifications')),
      if (p.isAdmin) ...[
        const SizedBox(height: 16),
        AdminSection(store: s),
        if (!hasOct) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: importOctober, icon: const Icon(Icons.download), label: const Text("Importer l'historique d'octobre 2026")),
        ],
      ],
      const SizedBox(height: 24),
      const Center(child: Brand(size: 40, showCountry: false)),
      const SizedBox(height: 6),
      const Center(child: Text('Repas Séguéla · version 1.2', style: TextStyle(color: K.muted, fontSize: 12))),
    ]);
  }
}

/// Administration : code d'accès du site et comptes des agents RH.
class AdminSection extends StatefulWidget {
  final Store store;
  const AdminSection({super.key, required this.store});
  @override
  State<AdminSection> createState() => _AdminSectionState();
}

class _AdminSectionState extends State<AdminSection> {
  final db = FirebaseFirestore.instance;

  Future<void> changeCode(String current) async {
    final c = TextEditingController(text: current);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Code d'accès du site"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Les nouveaux agents RH en ont besoin pour créer leur compte. Les comptes existants ne sont pas touchés.'),
          const SizedBox(height: 12),
          TextField(controller: c, decoration: const InputDecoration(labelText: 'Nouveau code (4 caractères minimum)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)), onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (v == null) return;
    if (v.length < 4) {
      Fx.error();
      if (mounted) snack(context, 'Le code compte au moins 4 caractères.');
      return;
    }
    try {
      await db.doc('config/access').update({'code': v});
      Fx.ok();
      if (mounted) snack(context, 'Code modifié.');
    } catch (e) {
      Fx.error();
      if (mounted) snack(context, 'Modification impossible : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.store.profile.uid;
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [
          Icon(Icons.admin_panel_settings, color: K.red),
          SizedBox(width: 8),
          Text('Administration', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 8),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: db.doc('config/access').snapshots(),
          builder: (context, snap) {
            final code = '${snap.data?.data()?['code'] ?? '…'}';
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Code d'accès du site"),
              subtitle: SelectableText(code, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: K.ink)),
              trailing: TextButton(onPressed: () => changeCode(code == '…' ? '' : code), child: const Text('Modifier')),
            );
          },
        ),
        const Divider(),
        const Text('Comptes des agents RH', style: TextStyle(fontWeight: FontWeight.w800)),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db.collection('users').snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) return const Padding(padding: EdgeInsets.all(12), child: Text('Chargement…', style: TextStyle(color: K.muted)));
            final users = snap.data!.docs.map((d) => AgentProfile.fromMap(d.id, d.data())).toList()..sort((a, b) => a.name.compareTo(b.name));
            return Column(children: [
              for (final u in users)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${u.name}${u.isAdmin ? ' · admin' : ''}'),
                  subtitle: Text(u.email),
                  value: u.active,
                  onChanged: u.uid == me
                      ? null
                      : (v) {
                          HapticFeedback.selectionClick();
                          db.doc('users/${u.uid}').update({'active': v});
                        },
                ),
              const Text('Désactivez un compte quand un agent quitte le service : il ne pourra plus rien voir.', style: TextStyle(color: K.muted, fontSize: 12)),
            ]);
          },
        ),
      ]),
    );
  }
}

// ===========================================================================
// ACCUEIL
// ===========================================================================
class AccueilTab extends StatelessWidget {
  final Store store;
  final VoidCallback onOrder;
  const AccueilTab({super.key, required this.store, required this.onOrder});

  String greeting() {
    final h = DateTime.now().hour;
    return h < 12 ? 'Bonjour' : (h < 18 ? 'Bon après-midi' : 'Bonsoir');
  }

  String dayName(String iso) {
    const days = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
    final d = parseIso(iso);
    return '${days[d.weekday - 1]} ${d.day} ${monthsFr[d.month - 1].toLowerCase()} ${d.year}';
  }

  /// Texte de la bande défilante : détails de la commande du jour sur une ligne.
  String tickerText(Order? o) {
    final t = todayIso();
    if (o == null || (!o.isSent && o.totals.total == 0)) {
      return 'COMMANDE DU ${dmy(t)} EN ATTENTE  •  Heure limite ${store.settings.deadline}  •  Ouvrez « Commande » pour la passer';
    }
    final x = o.totals;
    String part(bool pit, bool night) => o.lines
        .where((l) => l.isPit == pit)
        .map((l) => MapEntry(l.name, night ? l.foodNight : l.foodDay))
        .where((e) => e.value > 0)
        .map((e) => '${e.key} ${e.value}')
        .join(', ');
    final head = o.isSent ? 'COMMANDE DU ${dmy(o.date)}' : 'COMMANDE DU ${dmy(o.date)} (EN COURS · ${o.validatedCount}/${o.lines.length} validés)';
    final pl = part(false, false), pi = part(true, false), np = part(false, true), ni = part(true, true);
    return '$head  •  SUR PLACE ${x.place}${pl.isEmpty ? '' : ' ($pl)'}  •  BOLS PIT ${x.pit}${pi.isEmpty ? '' : ' ($pi)'}'
        '  •  TOTAL JOUR ${x.day}  •  NUIT ${x.night}${(np + ni).isEmpty ? '' : ' (${[np, ni].where((e) => e.isNotEmpty).join(', ')})'}'
        '${o.isSent ? '  •  Commande faite par ${o.author}${o.sentAt != null ? ' à ${hm(o.sentAt)}' : ''}' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final s = store;
    final o = s.todayOrder;
    final sent = o?.isSent ?? false;
    final t = o?.totals;
    final me = s.me;
    final first = s.profile.name.trim().split(RegExp(r'\s+')).last;
    // Résumé du mois
    final month = todayIso().substring(0, 7);
    final list = s.ordersOf(month);
    final monthPlats = list.fold<int>(0, (a, x) => a + x.totals.total);

    // Heure limite
    final p = s.settings.deadline.split(':');
    final now = DateTime.now();
    final lim = DateTime(now.year, now.month, now.day, int.tryParse(p[0]) ?? 8, int.tryParse(p.length > 1 ? p[1] : '20') ?? 20);
    final mins = (lim.difference(now).inSeconds / 60).round();
    String dur(int x) => x >= 60 ? '${x ~/ 60} h ${two(x % 60)}' : '$x min';

    return Column(children: [
      // Bande défilante rouge
      NewsTicker(text: tickerText(o)),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 18, 16, 24), children: [
          Row(children: [
            Avatar(profile: me, fallbackName: s.profile.name, size: 58),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${greeting()} $first', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                Text(dayName(todayIso()), style: const TextStyle(color: K.muted, fontSize: 14)),
              ]),
            ),
          ]),
          const SizedBox(height: 18),
          // Carte d'état de la commande du jour
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: sent ? const [Color(0xFF2F8A1F), Color(0xFF3A6B18)] : const [Color(0xFFE3191F), Color(0xFFA30E13)],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: (sent ? K.green : K.red).withValues(alpha: .35), blurRadius: 16, offset: const Offset(0, 6))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Icon(sent ? Icons.verified_rounded : Icons.pending_actions_rounded, color: Colors.white, size: 44),
              const SizedBox(height: 8),
              Text(sent ? 'COMMANDE DU JOUR\nEFFECTUÉE' : 'COMMANDE DU ${dmy(todayIso())}\nEN ATTENTE',
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900, height: 1.15, letterSpacing: .5)),
              const SizedBox(height: 14),
              if (sent && t != null) ...[
                Row(children: [
                  _BigTotal(label: 'TOTAL JOUR', value: t.day, sub: 'Sur place ${t.place} · Bols ${t.pit}'),
                  Container(width: 1, height: 70, color: Colors.white30),
                  _BigTotal(label: 'TOTAL NUIT', value: t.night, sub: 'Sur place ${t.nightPlace} · Pit ${t.nightPit}'),
                ]),
                const SizedBox(height: 14),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Avatar(profile: s.profileOf(o!.authorUid), fallbackName: o!.author, size: 28),
                  const SizedBox(width: 8),
                  Flexible(
                      child: Text('Par ${o!.author}${o!.sentAt != null ? ' à ${hm(o!.sentAt)}' : ''}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                ]),
              ] else ...[
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    mins >= 0 ? 'Heure limite ${s.settings.deadline}  ·  reste ${dur(mins)}' : 'Heure limite ${s.settings.deadline} dépassée de ${dur(-mins)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
                if (o != null && o.validatedCount > 0) ...[
                  const SizedBox(height: 8),
                  Text('${o.validatedCount} / ${o.lines.length} départements déjà validés',
                      textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: K.red, minimumSize: const Size.fromHeight(56)),
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    onOrder();
                  },
                  icon: const Icon(Icons.restaurant_menu, size: 26),
                  label: Text(o != null && o.validatedCount > 0 ? 'Continuer la commande' : 'Passer la commande', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                ),
              ],
            ]),
          ),
          if (sent) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: onOrder,
              icon: const Icon(Icons.visibility_outlined, color: K.muted),
              label: const Text('Voir le détail de la commande', style: TextStyle(color: K.muted, fontWeight: FontWeight.w700)),
            ),
          ],
          const SizedBox(height: 16),
          // Résumé du mois
          SectionCard(
            child: Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: K.redSoft, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.insights_rounded, color: K.red),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(monthLabelNice(month), style: const TextStyle(color: K.muted, fontWeight: FontWeight.w700, fontSize: 13)),
                  Text('${fmt(monthPlats)} plats  ·  ${list.length} jour(s)', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                const Text('MONTANT', style: TextStyle(color: K.muted, fontWeight: FontWeight.w800, fontSize: 11)),
                Text('${fmt(monthPlats * s.settings.price)} F', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: K.red)),
              ]),
            ]),
          ),
        ]),
      ),
    ]);
  }
}

class _BigTotal extends StatelessWidget {
  final String label, sub;
  final int value;
  const _BigTotal({required this.label, required this.value, required this.sub});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: .8)),
          Text(fmt(value), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 46, height: 1.05)),
          Text(sub, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
      );
}

/// Bande d'information rouge qui défile (texte d'une seule ligne).
class NewsTicker extends StatefulWidget {
  final String text;
  const NewsTicker({super.key, required this.text});
  @override
  State<NewsTicker> createState() => _NewsTickerState();
}

class _NewsTickerState extends State<NewsTicker> with SingleTickerProviderStateMixin {
  late final AnimationController ctrl = AnimationController(vsync: this);
  static const style = TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: .3);
  double textW = 0, boxW = 0;
  String shown = '';

  void setup(double w) {
    if (w == boxW && shown == widget.text) return;
    boxW = w;
    shown = widget.text;
    final tp = TextPainter(text: TextSpan(text: shown, style: style), textDirection: TextDirection.ltr, maxLines: 1)..layout();
    textW = tp.width;
    final dist = boxW + textW;
    ctrl.duration = Duration(milliseconds: (dist / 55 * 1000).round()); // ~55 px/s : lisible
    ctrl
      ..reset()
      ..repeat();
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      color: K.red,
      child: Row(children: [
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          color: K.redDark,
          alignment: Alignment.center,
          child: const Row(children: [
            Icon(Icons.campaign_rounded, color: Colors.white, size: 20),
            SizedBox(width: 4),
            Text('INFO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1)),
          ]),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setup(c.maxWidth);
            });
            return ClipRect(
              child: AnimatedBuilder(
                animation: ctrl,
                builder: (context, _) {
                  final x = boxW - (boxW + textW) * ctrl.value;
                  return Stack(clipBehavior: Clip.hardEdge, children: [
                    Positioned(
                      left: x,
                      top: 0,
                      bottom: 0,
                      child: Center(child: Text(widget.text, maxLines: 1, softWrap: false, style: style)),
                    ),
                  ]);
                },
              ),
            );
          }),
        ),
      ]),
    );
  }
}
