# Repas Séguéla — application Android

Application de commande journalière des repas (jour et nuit) pour **DESIMONE CI, site de Séguéla**.

- Chaque agent RH crée son compte (e-mail + mot de passe + **code d'accès du site**).
- Saisie de la présence et des plats par département, sur place et au pit (bols).
- Deux messages WhatsApp prêts à envoyer : la commande (restaurateur + comptable) et la répartition par département (équipe de partage).
- Confirmation d'envoi, verrouillage, rectificatif tracé avec motif.
- Historique partagé entre tous les agents, utilisable sans réseau (synchronisation au retour du réseau).
- Rapport Excel mensuel au format « DSCI FOOD QUANTITY RECORD SEGUELA », avec récapitulatif, cumul par département et historique.

Technologies, toutes gratuites : **Flutter** (Dart) pour l'application, **Firebase** (offre Spark gratuite) pour les comptes et les données, **GitHub Actions** pour fabriquer le fichier d'installation (APK).

---

## Mise en place (une seule fois, environ 20 minutes)

### 1. Firebase (comptes et base de données)
1. Ouvrir <https://console.firebase.google.com> avec un compte Google, puis **Créer un projet** nommé `repas-seguela`. Google Analytics n'est pas nécessaire : vous pouvez le désactiver.
2. Menu **Build › Authentication** › *Commencer* › onglet *Sign-in method* › **Adresse e-mail/Mot de passe** › Activer › Enregistrer.
3. Menu **Build › Firestore Database** › *Créer une base de données*. Choisir un emplacement en Europe (par exemple `eur3` ou `europe-west1`), puis le **mode production**.
4. Dans Firestore, onglet **Règles** : remplacer tout le contenu par celui du fichier `firestore.rules`, puis cliquer sur **Publier**.
5. Roue dentée › **Paramètres du projet** › *Vos applications* › icône **Android**.
   - Nom du package : `ci.desimone.repas_seguela` (exactement).
   - Surnom : Repas Séguéla.
   - Cliquer sur **Enregistrer l'application**, puis **télécharger `google-services.json`**. Les étapes suivantes de l'assistant Firebase (SDK, Gradle) peuvent être ignorées.

### 2. GitHub (fabrication de l'APK)
1. Créer un compte sur <https://github.com>, puis un dépôt **privé** nommé `repas-seguela`.
2. Y déposer le contenu de ce dossier, et ajouter le fichier `google-services.json` dans un dossier `firebase/`, ce qui donne `firebase/google-services.json`.
3. À chaque envoi sur la branche `main`, l'onglet **Actions** fabrique l'APK en 6 à 10 minutes. Le fichier apparaît dans **Releases** (`RepasSeguela-v1.0.X.apk`).

### 3. Installation sur les téléphones
1. Télécharger l'APK, puis l'envoyer aux agents RH par WhatsApp ou par câble.
2. Sur le téléphone : ouvrir le fichier, puis autoriser « Installer des applications inconnues » pour WhatsApp ou le gestionnaire de fichiers lorsque le téléphone le demande.
3. Les mises à jour s'installent par-dessus l'ancienne version, sans rien perdre : les données sont en ligne.

### 4. Premier lancement
1. **L'administrateur (vous)** crée son compte, puis coche **« Première installation (administrateur) »** et choisit le **code d'accès du site**.
2. Dans **Réglages**, il peut importer l'historique d'octobre 2026, saisir les numéros WhatsApp et ajuster les départements.
3. **Les autres agents RH** créent leur compte avec le code d'accès. L'administrateur peut désactiver un compte à tout moment (Réglages › Administration).

---

## Organisation du code

| Fichier | Rôle |
|---|---|
| `lib/main.dart` | Démarrage, thème, aiguillage connexion / profil |
| `lib/auth.dart` | Connexion, création de compte, code d'accès du site |
| `lib/data.dart` | Modèles (commande, départements, réglages) et synchronisation Firestore |
| `lib/home.dart` | Écrans : Commande, Envoi, Historique, Rapport, Réglages |
| `lib/messages.dart` | Textes des deux messages WhatsApp |
| `lib/report.dart` | Rapport Excel mensuel |
| `firestore.rules` | Règles de sécurité de la base de données |
| `.github/workflows/build-apk.yml` | Fabrication automatique de l'APK |
| `tool/` | Scripts de préparation Android, icône, clé de signature |

## Limites de l'offre gratuite Firebase
50 000 lectures et 20 000 écritures par jour, 1 Go de stockage. Une commande par jour et quelques agents représentent moins de 1 % de ces limites.
