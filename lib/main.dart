import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'auth.dart';
import 'data.dart';
import 'feedback.dart';
import 'theme.dart';
import 'firebase_options.dart';
import 'home.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: firebaseOptions);
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true, cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED);
  await Fx.init().timeout(const Duration(seconds: 4), onTimeout: () {});
  runApp(const RepasApp());
}

class RepasApp extends StatelessWidget {
  const RepasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Repas Séguéla',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      theme: appTheme(),
      home: const AuthGate(),
    );
  }
}

/// Aiguillage : connexion → profil RH → application.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const _Splash();
        final user = snap.data;
        if (user == null) return const LoginScreen();
        return ProfileGate(user: user);
      },
    );
  }
}

class ProfileGate extends StatefulWidget {
  final User user;
  const ProfileGate({super.key, required this.user});
  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> {
  Store? store;
  StreamSubscription? sub;
  AgentProfile? profile;
  bool missing = false;
  bool waited = false;

  @override
  void initState() {
    super.initState();
    sub = FirebaseFirestore.instance.doc('users/${widget.user.uid}').snapshots().listen((s) {
      if (!mounted) return;
      setState(() {
        if (s.exists && s.data() != null) {
          profile = AgentProfile.fromMap(widget.user.uid, s.data()!);
          missing = false;
          if (profile!.active) {
            if (store == null) {
              store = Store(profile!);
            } else {
              store!.updateProfile(profile!);
            }
          }
        } else if (!s.metadata.isFromCache) {
          missing = true;
        }
      });
    }, onError: (e) {
      if (mounted) setState(() => missing = true);
    });
    Future.delayed(const Duration(seconds: 12), () {
      if (mounted) setState(() => waited = true);
    });
  }

  @override
  void dispose() {
    sub?.cancel();
    store?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = profile;
    if (p != null && p.active && store != null) return HomeScreen(store: store!);
    if (p != null && !p.active) {
      return _Blocked(
          title: 'Compte désactivé',
          text: "Votre compte a été désactivé par l'administrateur. Contactez le responsable RH du site.",
          email: widget.user.email ?? '');
    }
    if (missing) return CompleteProfileScreen(user: widget.user);
    if (waited) {
      return _Blocked(
          title: 'Connexion lente',
          text: "Le profil n'a pas encore pu être chargé. Vérifiez la connexion internet du téléphone ; l'application continue d'essayer.",
          email: widget.user.email ?? '');
    }
    return const _Splash();
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Brand(size: 96),
            SizedBox(height: 28),
            Text('Repas Séguéla', style: TextStyle(color: K.ink, fontSize: 22, fontWeight: FontWeight.w800)),
            SizedBox(height: 4),
            Text('Commande journalière des repas', style: TextStyle(color: K.muted)),
            SizedBox(height: 24),
            CircularProgressIndicator(color: K.red),
          ]),
        ),
      );
}

class _Blocked extends StatelessWidget {
  final String title, text, email;
  const _Blocked({required this.title, required this.text, required this.email});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(text, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            Text('Compte : $email', style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 24),
            OutlinedButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('Se déconnecter')),
          ]),
        ),
      );
}
