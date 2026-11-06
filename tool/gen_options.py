"""Génère lib/firebase_options.dart à partir de firebase/google-services.json."""
import json, sys, os

src, dst = sys.argv[1], sys.argv[2]
PKG = "ci.desimone.repas_seguela"
if not os.path.exists(src):
    sys.exit("ERREUR : firebase/google-services.json est absent. Téléversez le fichier fourni par Firebase dans le dossier 'firebase' du dépôt.")
g = json.load(open(src, encoding="utf-8"))
info = g["project_info"]
clients = g.get("client", [])
c = next((x for x in clients if x["client_info"]["android_client_info"]["package_name"] == PKG), None)
if c is None:
    found = ", ".join(x["client_info"]["android_client_info"]["package_name"] for x in clients) or "aucun"
    sys.exit(f"ERREUR : l'application Android '{PKG}' n'est pas déclarée dans Firebase (trouvé : {found}).")
opts = {
    "apiKey": c["api_key"][0]["current_key"],
    "appId": c["client_info"]["mobilesdk_app_id"],
    "messagingSenderId": info["project_number"],
    "projectId": info["project_id"],
}
if info.get("storage_bucket"):
    opts["storageBucket"] = info["storage_bucket"]
body = "".join(f"  {k}: '{v}',\n" for k, v in opts.items())
open(dst, "w", encoding="utf-8").write(
    "// Généré automatiquement — ne pas modifier.\n"
    "import 'package:firebase_core/firebase_core.dart';\n\n"
    f"const FirebaseOptions firebaseOptions = FirebaseOptions(\n{body});\n")
print("firebase_options.dart généré pour le projet", info["project_id"])
