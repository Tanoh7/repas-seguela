import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'theme.dart';


String authError(Object e) {
  if (e is FirebaseAuthException) {
    switch (e.code) {
      case 'invalid-email':
        return "L'adresse e-mail n'est pas valide.";
      case 'email-already-in-use':
        return 'Un compte existe déjà avec cet e-mail. Connectez-vous.';
      case 'weak-password':
        return 'Mot de passe trop faible : 6 caractères minimum.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'E-mail ou mot de passe incorrect.';
      case 'too-many-requests':
        return 'Trop de tentatives. Patientez quelques minutes.';
      case 'network-request-failed':
        return "Pas de connexion internet. Réessayez quand le réseau revient.";
      case 'requires-recent-login':
        return 'Reconnectez-vous puis recommencez.';
    }
    return e.message ?? 'Erreur de connexion.';
  }
  if (e is FirebaseException && e.code == 'permission-denied') return "Accès refusé.";
  if (e is TimeoutException) return "Le réseau ne répond pas. Réessayez quand la connexion revient.";
  return 'Erreur : $e';
}

class _Header extends StatelessWidget {
  final String subtitle;
  const _Header(this.subtitle);
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: K.red, width: 4))),
        padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 28, 20, 22),
        child: Column(children: [
          const Brand(size: 78),
          const SizedBox(height: 18),
          const Text('Repas Séguéla', style: TextStyle(color: K.ink, fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(color: K.muted, fontSize: 15)),
        ]),
      );
}

class _ErrorBox extends StatelessWidget {
  final String? text;
  const _ErrorBox(this.text);
  @override
  Widget build(BuildContext context) => text == null
      ? const SizedBox.shrink()
      : Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFBE0DD), borderRadius: BorderRadius.circular(8)),
          child: Text(text!, style: const TextStyle(color: Color(0xFFB42318))),
        );
}

// ---------------------------------------------------------------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController(), pass = TextEditingController();
  bool busy = false, register = false, hide = true;
  final pass2 = TextEditingController();
  String? err, info;

  Future<void> submit() async {
    setState(() {
      err = null;
      info = null;
    });
    final e = email.text.trim(), p = pass.text;
    if (e.isEmpty || p.isEmpty) {
      setState(() => err = 'Saisissez votre e-mail et votre mot de passe.');
      return;
    }
    if (register && p != pass2.text) {
      setState(() => err = 'Les deux mots de passe ne correspondent pas.');
      return;
    }
    setState(() => busy = true);
    try {
      if (register) {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(email: e, password: p);
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(email: e, password: p);
      }
    } catch (x) {
      if (mounted) setState(() => err = authError(x));
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> reset() async {
    final e = email.text.trim();
    if (e.isEmpty) {
      setState(() => err = 'Saisissez votre e-mail, puis touchez « Mot de passe oublié ».');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: e);
      setState(() {
        err = null;
        info = 'Un e-mail de réinitialisation a été envoyé à $e.';
      });
    } catch (x) {
      setState(() => err = authError(x));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(padding: EdgeInsets.zero, children: [
        _Header(register ? 'Créer mon compte RH' : 'Connexion des agents RH'),
        Padding(
          padding: const EdgeInsets.all(20),
          child: AutofillGroup(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _ErrorBox(err),
              if (info != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFD9F0E2), borderRadius: BorderRadius.circular(8)),
                  child: Text(info!),
                ),
              TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'E-mail')),
              const SizedBox(height: 12),
              TextField(
                controller: pass,
                obscureText: hide,
                autofillHints: [register ? AutofillHints.newPassword : AutofillHints.password],
                decoration: InputDecoration(
                  labelText: 'Mot de passe',
                  suffixIcon: IconButton(icon: Icon(hide ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => hide = !hide)),
                ),
              ),
              if (register) ...[
                const SizedBox(height: 12),
                TextField(controller: pass2, obscureText: hide, decoration: const InputDecoration(labelText: 'Confirmer le mot de passe')),
                const SizedBox(height: 8),
                const Text("Après la création du compte, l'application vous demandera votre nom et le code d'accès du site.",
                    style: TextStyle(color: Colors.black54)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: busy ? null : submit,
                child: busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(register ? 'Créer mon compte' : 'Se connecter'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: busy ? null : () => setState(() {
                  register = !register;
                  err = null;
                  info = null;
                }),
                child: Text(register ? "J'ai déjà un compte : me connecter" : 'Nouvel agent RH : créer mon compte'),
              ),
              if (!register) TextButton(onPressed: busy ? null : reset, child: const Text('Mot de passe oublié')),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
/// Après la création du compte : nom + code d'accès du site (ou première installation).
class CompleteProfileScreen extends StatefulWidget {
  final User user;
  const CompleteProfileScreen({super.key, required this.user});
  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final name = TextEditingController(), code = TextEditingController(), code2 = TextEditingController();
  bool firstInstall = false, busy = false;
  String? err;

  Future<void> submit() async {
    setState(() => err = null);
    final n = name.text.trim(), c = code.text.trim();
    if (n.length < 3) {
      setState(() => err = 'Saisissez votre nom et prénom.');
      return;
    }
    if (c.length < 4) {
      setState(() => err = "Le code d'accès compte au moins 4 caractères.");
      return;
    }
    if (firstInstall && c != code2.text.trim()) {
      setState(() => err = 'Les deux codes ne correspondent pas.');
      return;
    }
    setState(() => busy = true);
    final db = FirebaseFirestore.instance, uid = widget.user.uid;
    final now = DateTime.now().toUtc().toIso8601String();
    final profile = {
      'name': n,
      'email': widget.user.email ?? '',
      'role': firstInstall ? 'admin' : 'rh',
      'active': true,
      'siteCode': c,
      'createdAt': now,
    };
    try {
      if (firstInstall) {
        final b = db.batch();
        b.set(db.doc('config/access'), {'code': c, 'adminUid': uid, 'createdAt': now});
        b.set(db.doc('users/$uid'), profile);
        await b.commit().timeout(const Duration(seconds: 25));
      } else {
        await db.doc('users/$uid').set(profile).timeout(const Duration(seconds: 25));
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() => err = e.code == 'permission-denied'
            ? (firstInstall
                ? "Le site est déjà configuré. Demandez le code d'accès au responsable RH et décochez « Première installation »."
                : "Code d'accès du site incorrect. Demandez-le au responsable RH.")
            : authError(e));
      }
    } catch (e) {
      if (mounted) setState(() => err = authError(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(padding: EdgeInsets.zero, children: [
        const _Header('Finaliser mon compte'),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Compte : ${widget.user.email ?? ''}', style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 16),
            _ErrorBox(err),
            TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nom et prénom', helperText: 'Apparaît dans « Commande faite par »')),
            const SizedBox(height: 16),
            TextField(
                controller: code,
                decoration: InputDecoration(
                    labelText: firstInstall ? "Choisir le code d'accès du site" : "Code d'accès du site",
                    helperText: firstInstall ? 'Vous le donnerez aux autres agents RH.' : 'Fourni par le responsable RH.')),
            if (firstInstall) ...[
              const SizedBox(height: 12),
              TextField(controller: code2, decoration: const InputDecoration(labelText: 'Confirmer le code')),
            ],
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: firstInstall,
              onChanged: busy ? null : (v) => setState(() => firstInstall = v ?? false),
              title: const Text('Première installation (administrateur)'),
              subtitle: const Text("Uniquement pour la toute première personne qui configure l'application."),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: busy ? null : submit,
              child: busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Valider'),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: busy ? null : () => FirebaseAuth.instance.signOut(), child: const Text('Se déconnecter')),
          ]),
        ),
      ]),
    );
  }
}
