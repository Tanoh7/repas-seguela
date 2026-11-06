import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data.dart';
import 'messages.dart';
import 'report.dart';

const cBrand = Color(0xFF0E5A49);
const cBrandSoft = Color(0xFFD7EBE4);
const cOchre = Color(0xFFB7791A);
const cOchreSoft = Color(0xFFF7E9CD);
const cOk = Color(0xFF1C7A49);
const cOkSoft = Color(0xFFD9F0E2);
const cWarn = Color(0xFFA35A08);
const cWarnSoft = Color(0xFFFBE8D0);
const cBad = Color(0xFFB42318);
const cBadSoft = Color(0xFFFBE0DD);
const cMuted = Color(0xFF5A6A64);
const cLine = Color(0xFFD3DCD7);
const cWa = Color(0xFF1FA855);

void snack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
}

Widget notice(String text, {Color bg = cWarnSoft, Color fg = cWarn, Widget? action}) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(text, style: TextStyle(color: fg, fontSize: 14)),
        if (action != null) action,
      ]),
    );

Widget pill(String text, Color bg, Color fg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(text.toUpperCase(), style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .5)),
    );

Widget statusPill(Order? o) {
  if (o == null) return pill('Aucune', const Color(0xFFE3E9E5), cMuted);
  if (o.isSent) return o.isRectified ? pill('Rectifiée', cOchreSoft, cOchre) : pill('Envoyée', cOkSoft, cOk);
  return o.isRectified ? pill('Rectif. en cours', cOchreSoft, cOchre) : pill('Brouillon', cWarnSoft, cWarn);
}

class SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const SectionCard({super.key, required this.child, this.padding = const EdgeInsets.all(14)});
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: cLine), borderRadius: BorderRadius.circular(10)),
        child: child,
      );
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

  void go(int i) {
    widget.store.flush();
    setState(() => tab = i);
  }

  Widget deadlineChip(Store s) {
    String text;
    Color bg = Colors.white24, fg = Colors.white;
    if (s.cur.isSent) {
      text = 'Envoyée ${hm(s.cur.sentAt)}'.trim();
      bg = Colors.white;
      fg = cBrand;
    } else if (s.date != todayIso()) {
      text = dmy(s.date);
    } else {
      final p = s.settings.deadline.split(':');
      final now = DateTime.now();
      final lim = DateTime(now.year, now.month, now.day, int.tryParse(p[0]) ?? 8, int.tryParse(p.length > 1 ? p[1] : '20') ?? 20);
      final m = (lim.difference(now).inSeconds / 60).round();
      String d(int x) => x >= 60 ? '${x ~/ 60} h ${two(x % 60)}' : '$x min';
      if (m >= 0) {
        text = 'Limite ${s.settings.deadline} · ${d(m)}';
      } else {
        text = 'Retard · ${d(-m)}';
        bg = cBad;
      }
    }
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 13)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          titleSpacing: 16,
          title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Repas Séguéla', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
            Text('DESIMONE CI · SÉGUÉLA', style: TextStyle(fontSize: 11, color: Colors.white70, letterSpacing: .8)),
          ]),
          actions: [Center(child: deadlineChip(s))],
        ),
        body: Column(children: [
          if (s.error != null) Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: notice(s.error!, bg: cBadSoft, fg: cBad)),
          if (s.pendingSync)
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: notice('Hors connexion : les modifications sont gardées sur le téléphone et seront envoyées dès que le réseau revient.')),
          Expanded(
            child: IndexedStack(index: tab, children: [
              CommandeTab(store: s, onSend: () => go(1)),
              EnvoiTab(store: s, onEdit: () => go(0)),
              HistoriqueTab(store: s, onOpen: (d) {
                s.goDate(d);
                go(0);
              }),
              RapportTab(store: s),
              ReglagesTab(store: s),
            ]),
          ),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: go,
          height: 64,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.edit_note_outlined), selectedIcon: Icon(Icons.edit_note), label: 'Commande'),
            NavigationDestination(icon: Icon(Icons.send_outlined), selectedIcon: Icon(Icons.send), label: 'Envoi'),
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
  String shift = 'jour';

  Future<void> pickDate() async {
    final s = widget.store;
    final d = await showDatePicker(
      context: context,
      initialDate: parseIso(s.date),
      firstDate: DateTime(2025, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (d != null) s.goDate(isoOf(d));
  }

  Future<void> copyPrev() async {
    final s = widget.store;
    if (s.cur.lines.any((l) => l.hasValues)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Remplacer les chiffres ?'),
          content: const Text('Les chiffres déjà saisis seront remplacés par ceux de la dernière commande.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remplacer')),
          ],
        ),
      );
      if (ok != true) return;
    }
    final d = s.copyPrevious();
    if (!mounted) return;
    snack(context, d == null ? 'Aucune commande précédente à reprendre.' : 'Chiffres repris du ${dmy(d)}. Vérifiez-les.');
  }

  Widget zone(Store s, bool pit, String title) {
    final pk = shift == 'jour' ? 'pj' : 'pn';
    final rows = s.cur.lines.where((l) => l.isPit == pit).toList();
    final sum = rows.fold<int>(0, (a, l) => a + (shift == 'jour' ? l.foodDay : l.foodNight));
    final locked = s.locked;
    return Container(
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: cLine), borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Container(
          color: pit ? cOchreSoft : cBrandSoft,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
            Text(fmt(sum), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 2),
          child: Row(children: [
            Expanded(child: Text('DÉPARTEMENT', style: TextStyle(fontSize: 11, color: cMuted, fontWeight: FontWeight.w700))),
            SizedBox(width: 80, child: Text('PRÉSENCE', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: cMuted, fontWeight: FontWeight.w700))),
            SizedBox(width: 8),
            SizedBox(width: 80, child: Text('PLATS', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: cMuted, fontWeight: FontWeight.w700))),
          ]),
        ),
        for (final l in rows)
          Container(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: cLine))),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(children: [
              Expanded(child: _DeptName(line: l, night: shift != 'jour')),
              SizedBox(
                width: 80,
                child: NumField(
                  key: ValueKey('${s.rev}|${s.date}|$shift|${l.id}|p'),
                  initial: shift == 'jour' ? l.pj : l.pn,
                  hint: '0',
                  enabled: !locked,
                  label: 'Présence ${l.name}',
                  onChanged: (v) => s.edit((o) {
                    final x = o.lines.firstWhere((e) => e.id == l.id);
                    if (pk == 'pj') {
                      x.pj = v;
                    } else {
                      x.pn = v;
                    }
                  }),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: NumField(
                  key: ValueKey('${s.rev}|${s.date}|$shift|${l.id}|f'),
                  initial: shift == 'jour' ? l.fj : l.fn,
                  hint: '${(shift == 'jour' ? l.pj : l.pn) ?? 0}',
                  enabled: !locked,
                  label: 'Plats ${l.name}',
                  onChanged: (v) => s.edit((o) {
                    final x = o.lines.firstWhere((e) => e.id == l.id);
                    if (shift == 'jour') {
                      x.fj = v;
                    } else {
                      x.fn = v;
                    }
                  }),
                ),
              ),
            ]),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final o = s.cur, t = o.totals;
    Widget status;
    if (o.isSent) {
      status = pill('Envoyée${o.sentAt != null ? ' · ${hm(o.sentAt)}' : ''}', cOkSoft, cOk);
    } else if (s.exists || s.dirty) {
      status = o.isRectified ? pill('Rectification en cours', cOchreSoft, cOchre) : pill('Brouillon enregistré', cWarnSoft, cWarn);
    } else {
      status = pill('Nouvelle commande', const Color(0xFFE3E9E5), cMuted);
    }
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 20), children: [
          Row(children: [
            IconButton.outlined(onPressed: () => s.goDate(addDays(s.date, -1)), icon: const Icon(Icons.chevron_left), tooltip: 'Jour précédent'),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: pickDate,
                icon: const Icon(Icons.event),
                label: Text('${s.date == todayIso() ? "Aujourd'hui · " : ''}${dmy(s.date)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(onPressed: () => s.goDate(addDays(s.date, 1)), icon: const Icon(Icons.chevron_right), tooltip: 'Jour suivant'),
          ]),
          const SizedBox(height: 12),
          Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8, spacing: 8, children: [
            status,
            if (!s.locked) TextButton.icon(onPressed: copyPrev, icon: const Icon(Icons.content_copy, size: 18), label: const Text('Reprendre la veille')),
          ]),
          if (s.locked) ...[
            const SizedBox(height: 10),
            notice('Commande envoyée${o.author.isNotEmpty ? ' par ${o.author}' : ''}. Pour la corriger, utilisez « Rectifier » dans l\'onglet Envoi.', bg: cOkSoft, fg: cOk),
          ],
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'jour', label: Text('Jour'), icon: Icon(Icons.wb_sunny_outlined)),
              ButtonSegment(value: 'nuit', label: Text('Nuit'), icon: Icon(Icons.nightlight_outlined)),
            ],
            selected: {shift},
            onSelectionChanged: (v) => setState(() => shift = v.first),
          ),
          const SizedBox(height: 10),
          const Text('Saisissez la présence. Le nombre de plats reprend la présence ; corrigez-le seulement s\'il est différent.',
              style: TextStyle(color: cMuted, fontSize: 13)),
          const SizedBox(height: 12),
          zone(s, false, shift == 'jour' ? 'Sur place' : 'Nuit · sur place'),
          const SizedBox(height: 12),
          zone(s, true, shift == 'jour' ? 'Au pit · plats en bol' : 'Nuit · au pit'),
          const SizedBox(height: 14),
          Text('Commande faite par : ${o.isSent ? o.author : s.profile.name}', style: const TextStyle(color: cMuted)),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: widget.onSend, icon: const Icon(Icons.send), label: const Text('Préparer les messages')),
        ]),
      ),
      Container(
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: cLine))),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Row(children: [
          _Total('Sur place', t.place),
          _Total('Bols pit', t.pit),
          _Total('Total jour', t.day, key_: true),
          _Total('Nuit', t.night, key_: true),
        ]),
      ),
    ]);
  }
}

class _DeptName extends StatelessWidget {
  final Line line;
  final bool night;
  const _DeptName({required this.line, required this.night});
  @override
  Widget build(BuildContext context) {
    final p = night ? line.pn : line.pj, f = night ? line.fn : line.fj;
    final diff = (p != null && f != null && f != p) ? f - p : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(line.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      if (diff != null) Text('${diff > 0 ? '+' : ''}$diff / présence', style: const TextStyle(fontSize: 12, color: cMuted)),
    ]);
  }
}

class _Total extends StatelessWidget {
  final String label;
  final int value;
  final bool key_;
  const _Total(this.label, this.value, {this.key_ = false});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Text(fmt(value), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: key_ ? cBrand : Colors.black87)),
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, color: cMuted, fontWeight: FontWeight.w700)),
        ]),
      );
}

class NumField extends StatefulWidget {
  final int? initial;
  final String hint, label;
  final bool enabled;
  final ValueChanged<int?> onChanged;
  const NumField({super.key, required this.initial, required this.hint, required this.enabled, required this.onChanged, required this.label});
  @override
  State<NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<NumField> {
  late final TextEditingController c = TextEditingController(text: widget.initial?.toString() ?? '');
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: widget.label,
        child: TextField(
          controller: c,
          enabled: widget.enabled,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
          textAlign: TextAlign.center,
          textInputAction: TextInputAction.next,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: const TextStyle(color: Color(0xFFA0ACA7)),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            fillColor: widget.enabled ? const Color(0xFFF3F6F4) : Colors.transparent,
            border: widget.enabled ? const OutlineInputBorder() : InputBorder.none,
          ),
          onChanged: (v) => widget.onChanged(v.isEmpty ? null : int.tryParse(v)),
        ),
      );
}

// ===========================================================================
// ENVOI
// ===========================================================================
class EnvoiTab extends StatelessWidget {
  final Store store;
  final VoidCallback onEdit;
  const EnvoiTab({super.key, required this.store, required this.onEdit});

  Future<void> openWa(BuildContext context, String phone, String text) async {
    store.flush();
    final ok = await launchUrl(whatsappUri(phone, text), mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && context.mounted) snack(context, "WhatsApp n'a pas pu s'ouvrir. Utilisez « Copier ».");
  }

  Future<void> copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
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
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Rectifier')),
        ],
      ),
    );
    if (reason == null) return;
    if (reason.isEmpty) {
      if (context.mounted) snack(context, 'Indiquez le motif de la rectification.');
      return;
    }
    store.rectify(reason);
    onEdit();
    if (context.mounted) snack(context, 'Corrigez les chiffres puis renvoyez le rectificatif.');
  }

  Widget msgCard(BuildContext context, String title, String sub, String text, List<Widget> buttons) => SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          Text(sub, style: const TextStyle(color: cMuted, fontSize: 13)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFE9EEEB), borderRadius: BorderRadius.circular(8)),
            child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5, height: 1.4)),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: buttons),
        ]),
      );

  Widget waBtn(BuildContext context, String label, String phone, String text) => FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: cWa, minimumSize: const Size(0, 46)),
        onPressed: () => openWa(context, phone, text),
        icon: const Icon(Icons.chat),
        label: Text(label),
      );

  Widget smallBtn(String label, IconData icon, VoidCallback f) =>
      OutlinedButton.icon(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)), onPressed: f, icon: Icon(icon, size: 18), label: Text(label));

  @override
  Widget build(BuildContext context) {
    final o = store.cur, t = o.totals, st = store.settings;
    final view = o.copy()..author = o.isSent ? o.author : store.profile.name;
    final m1 = orderMessage(view), m2 = sharingMessage(view);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
      Text('Envoi du ${dmy(o.date)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      if (t.total == 0) ...[
        notice('Aucun plat saisi pour cette date.', action: TextButton(onPressed: onEdit, child: const Text('Retour à la saisie'))),
        const SizedBox(height: 10),
      ],
      msgCard(context, '1 · Commande', 'Au restaurateur et au comptable', m1, [
        waBtn(context, 'Restaurateur', st.phoneResto, m1),
        waBtn(context, 'Comptable', st.phoneCompta, m1),
        smallBtn('Copier', Icons.copy, () => copy(context, m1)),
        smallBtn('Partager', Icons.share, () => Share.share(m1)),
      ]),
      const SizedBox(height: 12),
      msgCard(context, '2 · Répartition par département', "À l'équipe de gestion et de partage", m2, [
        waBtn(context, 'Équipe partage', st.phonePartage, m2),
        smallBtn('Copier', Icons.copy, () => copy(context, m2)),
        smallBtn('Partager', Icons.share, () => Share.share(m2)),
      ]),
      const SizedBox(height: 16),
      if (o.isSent) ...[
        notice('Envoi confirmé${o.sentAt != null ? ' à ${hm(o.sentAt)}' : ''}${o.author.isNotEmpty ? ' par ${o.author}' : ''}. La commande est verrouillée.', bg: cOkSoft, fg: cOk),
        for (final r in o.revisions)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
                'Rectifiée le ${dmy('${r['at']}'.substring(0, 10))} à ${hm('${r['at']}')} par ${r['by'] ?? ''} : ${r['reason'] ?? ''} (avant : jour ${(r['before'] as Map?)?['day'] ?? '?'}, nuit ${(r['before'] as Map?)?['night'] ?? '?'})',
                style: const TextStyle(color: cMuted, fontSize: 13)),
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: cBad, side: const BorderSide(color: cBad)),
          onPressed: () => rectify(context),
          icon: const Icon(Icons.edit),
          label: const Text('Rectifier cette commande'),
        ),
      ] else ...[
        const Text('Après l\'envoi des deux messages sur WhatsApp, confirmez ici. La commande sera verrouillée et datée.', style: TextStyle(color: cMuted)),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: t.total == 0
              ? null
              : () {
                  store.confirmSent();
                  snack(context, 'Commande confirmée et verrouillée.');
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
        onTap: () => widget.onOpen(k),
        child: Container(
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: cLine))),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            SizedBox(width: 92, child: Text(dmy(k), style: TextStyle(fontWeight: FontWeight.w600, color: o == null ? cMuted : Colors.black87))),
            Expanded(
                child: Text(t == null ? '—' : 'Jour ${t.day} (${t.place} + ${t.pit})  ·  Nuit ${t.night}',
                    style: TextStyle(color: o == null ? cMuted : Colors.black87, fontSize: 13))),
            if (t != null) Padding(padding: const EdgeInsets.only(right: 8), child: Text('${t.total}', style: const TextStyle(fontWeight: FontWeight.w800))),
            statusPill(o),
          ]),
        ),
      ));
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
      Row(children: [
        const Expanded(child: Text('Historique', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700))),
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
            color: const Color(0xFFE3E9E5),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(children: [
              const Expanded(child: Text('TOTAL', style: TextStyle(fontWeight: FontWeight.w800))),
              Text('Jour ${fmt(day)} · Nuit ${fmt(night)} · ${fmt(total)} plats', style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 8),
      const Text('Touchez une ligne pour ouvrir la commande.', style: TextStyle(color: cMuted, fontSize: 13)),
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
    try {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final bytes = buildReport(month: m, orders: widget.store.orders, price: widget.store.settings.price);
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/${reportFileName(m)}');
      await f.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [XFile(f.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
        subject: 'Rapport repas ${monthLabelNice(m)} — DSCI Séguéla',
        text: 'Bonjour, veuillez trouver ci-joint le rapport des commandes de repas de ${monthLabelNice(m).toLowerCase()} (DSCI Séguéla).',
      );
    } catch (e) {
      if (mounted) snack(context, "Le rapport n'a pas pu être créé : $e");
    }
    if (mounted) setState(() => busy = false);
  }

  Widget kpi(String label, String value, {bool money = false, String? sub}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: money ? cBrand : Colors.white, border: Border.all(color: money ? cBrand : cLine), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: money ? Colors.white70 : cMuted)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: money ? 28 : 26, fontWeight: FontWeight.w800, color: money ? Colors.white : Colors.black87)),
          if (sub != null) Text(sub, style: TextStyle(fontSize: 12, color: money ? Colors.white70 : cMuted)),
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
    final ids = agg.keys.toList()..sort((a, b) => (agg[a]![1] == 'pit' ? 1 : 0).compareTo(agg[b]![1] == 'pit' ? 1 : 0));
    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
      Row(children: [
        const Expanded(child: Text('Rapport mensuel', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700))),
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
      if (warn.isNotEmpty) notice(warn.join(' ')) else if (list.isNotEmpty) notice('Toutes les commandes du mois sont confirmées.', bg: cOkSoft, fg: cOk),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: (list.isEmpty || busy) ? null : () => export(m),
        icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.table_view),
        label: Text(busy ? 'Préparation…' : 'Créer et envoyer le rapport Excel'),
      ),
      const SizedBox(height: 6),
      const Text(
          "Le fichier contient le récapitulatif du mois avec montants, le cumul par département, l'historique de tous les mois, puis une feuille par jour au format habituel. Vous choisissez ensuite l'application d'envoi (e-mail, WhatsApp…).",
          style: TextStyle(color: cMuted, fontSize: 13)),
      const SizedBox(height: 14),
      SectionCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          Container(
            color: const Color(0xFFE3E9E5),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: const Row(children: [
              Expanded(child: Text('DÉPARTEMENT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cMuted))),
              SizedBox(width: 60, child: Text('JOUR', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cMuted))),
              SizedBox(width: 56, child: Text('NUIT', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cMuted))),
              SizedBox(width: 96, child: Text('MONTANT', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cMuted))),
            ]),
          ),
          if (ids.isEmpty) const Padding(padding: EdgeInsets.all(14), child: Text('Aucune commande ce mois-ci.', style: TextStyle(color: cMuted))),
          for (final id in ids)
            Container(
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: cLine))),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(children: [
                Expanded(child: Text('${agg[id]![0]}${agg[id]![1] == 'pit' ? ' · pit' : ''}')),
                SizedBox(width: 60, child: Text(fmt(agg[id]![2] as int), textAlign: TextAlign.right)),
                SizedBox(width: 56, child: Text(fmt(agg[id]![3] as int), textAlign: TextAlign.right)),
                SizedBox(
                    width: 96,
                    child: Text(fmt(((agg[id]![2] as int) + (agg[id]![3] as int)) * price), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
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
      if (mounted) snack(context, 'Réglages enregistrés.');
    } on TimeoutException {
      if (mounted) snack(context, 'Réglages gardés sur le téléphone ; ils seront envoyés dès que le réseau revient.');
    } catch (e) {
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
      if (mounted) snack(context, n == 0 ? 'Octobre 2026 est déjà dans l\'historique.' : '$n jours d\'octobre 2026 importés.');
    } catch (e) {
      if (mounted) snack(context, 'Import impossible : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    if (!loadedForm) loadForm();
    final p = s.profile;
    final hasOct = s.orders.keys.any((k) => k.startsWith('2026-10'));
    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 32), children: [
      const Text('Réglages', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      SectionCard(
        child: Row(children: [
          CircleAvatar(backgroundColor: cBrandSoft, child: Text(p.name.isEmpty ? '?' : p.name[0].toUpperCase(), style: const TextStyle(color: cBrand, fontWeight: FontWeight.w700))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              Text('${p.email} · ${p.isAdmin ? 'Administrateur' : 'Agent RH'}', style: const TextStyle(color: cMuted, fontSize: 13)),
            ]),
          ),
          TextButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('Déconnexion')),
        ]),
      ),
      const SizedBox(height: 12),
      SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Commande', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
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
              style: TextStyle(color: cMuted, fontSize: 13)),
          const SizedBox(height: 10),
          TextField(controller: resto, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Restaurateur')),
          const SizedBox(height: 10),
          TextField(controller: compta, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Comptable')),
          const SizedBox(height: 10),
          TextField(controller: partage, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Équipe gestion et partage')),
        ]),
      ),
      const SizedBox(height: 12),
      SectionCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Départements', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const Text("L'ordre ici est l'ordre de saisie et des feuilles Excel.", style: TextStyle(color: cMuted, fontSize: 13)),
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
                    icon: const Icon(Icons.close, color: cBad)),
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
      const SizedBox(height: 20),
      const Center(child: Text('Repas Séguéla · version 1.0', style: TextStyle(color: cMuted, fontSize: 12))),
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
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (v == null) return;
    if (v.length < 4) {
      if (mounted) snack(context, 'Le code compte au moins 4 caractères.');
      return;
    }
    try {
      await db.doc('config/access').update({'code': v});
      if (mounted) snack(context, 'Code modifié.');
    } catch (e) {
      if (mounted) snack(context, 'Modification impossible : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.store.profile.uid;
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Administration', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: db.doc('config/access').snapshots(),
          builder: (context, snap) {
            final code = '${snap.data?.data()?['code'] ?? '…'}';
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Code d'accès du site"),
              subtitle: SelectableText(code, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 1)),
              trailing: TextButton(onPressed: () => changeCode(code == '…' ? '' : code), child: const Text('Modifier')),
            );
          },
        ),
        const Divider(),
        const Text('Comptes des agents RH', style: TextStyle(fontWeight: FontWeight.w700)),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: db.collection('users').snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) return const Padding(padding: EdgeInsets.all(12), child: Text('Chargement…', style: TextStyle(color: cMuted)));
            final users = snap.data!.docs.map((d) => AgentProfile.fromMap(d.id, d.data())).toList()..sort((a, b) => a.name.compareTo(b.name));
            return Column(children: [
              for (final u in users)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${u.name}${u.isAdmin ? ' · admin' : ''}'),
                  subtitle: Text(u.email),
                  value: u.active,
                  onChanged: u.uid == me ? null : (v) => db.doc('users/${u.uid}').update({'active': v}),
                ),
              const Text('Désactivez un compte quand un agent quitte le service : il ne pourra plus rien voir.', style: TextStyle(color: cMuted, fontSize: 12)),
            ]);
          },
        ),
      ]),
    );
  }
}
