"""Ajuste le projet Android généré par 'flutter create' : minSdk, nom affiché, icône."""
import os, re, shutil, glob

app = "android/app"
gradle = next(p for p in (f"{app}/build.gradle.kts", f"{app}/build.gradle") if os.path.exists(p))
s = open(gradle, encoding="utf-8").read()
s2 = re.sub(r"minSdk(Version)?\s*=?\s*flutter\.minSdkVersion", "minSdk = 23" if gradle.endswith(".kts") else "minSdkVersion 23", s)
if s2 == s and "minSdk" in s:
    s2 = re.sub(r"minSdk(Version)?\s*=?\s*\d+", "minSdk = 23" if gradle.endswith(".kts") else "minSdkVersion 23", s)
open(gradle, "w", encoding="utf-8").write(s2)
print("minSdk ->", re.findall(r"minSdk[^\n]*", s2))

man = f"{app}/src/main/AndroidManifest.xml"
m = open(man, encoding="utf-8").read()
m = re.sub(r'android:label="[^"]*"', 'android:label="Repas Séguéla"', m, count=1)
open(man, "w", encoding="utf-8").write(m)

for src in glob.glob("tool/icons/mipmap-*/ic_launcher.png"):
    d = f"{app}/src/main/res/" + src.split("/")[2]
    os.makedirs(d, exist_ok=True)
    shutil.copy(src, d + "/ic_launcher.png")
print("Projet Android prêt.")
