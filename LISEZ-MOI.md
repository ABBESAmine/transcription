# Clé d'installation — Transcription de séance

Copie **tout le contenu de ce dossier** à la racine d'une clé USB, puis,
sur la machine à équiper : double-clic sur **`INSTALLER.bat`**.

---

## Ce qui se passe à l'installation

1. Une fenêtre demande **où installer**. Le point de départ est `C:\`, et
   un dossier `TRANS_CRIPTION_AUDIO` sera créé à l'endroit choisi.
   Annuler cette fenêtre revient à accepter `C:\TRANS_CRIPTION_AUDIO`.
2. Le script regarde la machine et **adapte les réglages** : nombre de
   threads calé sur le nombre de cœurs, et proposition de rétrograder au
   modèle `small` si la machine a moins de 8 Go de RAM.
3. Une question : installer aussi le **second moteur, whisper.cpp**
   (celui de Handy) ? Compter 560 Mo de plus.
4. Un récapitulatif s'affiche. Rien n'est écrit sur le disque avant que
   tu aies cliqué sur OK.
5. **Python** et **ffmpeg** sont installés s'ils manquent (par winget).
6. L'environnement Python, faster-whisper et le modèle sont mis en place.
7. `Lancer.bat`, `transcription.ini`, le **raccourci sur le Bureau** et
   le désinstalleur sont créés. Une dernière fenêtre propose de démarrer
   l'application.

Compter **10 à 20 minutes**, selon ce qu'il faut télécharger.

---

## Contenu de la clé

```
Racine de la cle\
│
├─ INSTALLER.bat        ← double-clic pour installer
├─ DESINSTALLER.bat     ← double-clic pour desinstaller
├─ LISEZ-MOI.md         ← ce fichier
│
├─ scripts\             les deux scripts PowerShell
├─ application\         transcription_gui.py
├─ modeles\             le modele faster-whisper
└─ whisper-cpp\         le second moteur (facultatif)
```

| Élément | Taille | Rôle |
|---|---|---|
| `INSTALLER.bat` | 1 Ko | à double-cliquer pour installer |
| `DESINSTALLER.bat` | 1 Ko | à double-cliquer pour désinstaller |
| `LISEZ-MOI.md` | 6 Ko | ce fichier |
| `scripts\` | 38 Ko | les deux scripts appelés par les `.bat` |
| `application\` | 40 Ko | l'application elle-même |
| `modeles\faster-whisper-large-v3\` | **2,88 Go** | le modèle, pour installer sans Internet |
| `whisper-cpp\` *(facultatif)* | 560 Mo | le second moteur, voir ci-dessous |

Compter une clé de **4 Go minimum**, 8 Go si tu y ajoutes whisper.cpp.

Les trois fichiers de la racine sont les seuls à manipuler. Les `.bat`
retrouvent leur script dans `scripts\`, et à défaut à côté d'eux — c'est
ainsi que le désinstalleur fonctionne aussi une fois déposé, à plat, dans
le dossier d'installation.

### Le modèle voyage sur la clé

Le dossier `modeles\faster-whisper-large-v3\` évite le téléchargement de
2,88 Go sur chaque machine. Le script le copie dans l'installation et
règle le `.ini` pour pointer dessus. Rien à faire.

Pour préparer un autre modèle — `medium`, `small` ou `base` — le dossier
doit s'appeler `modeles\faster-whisper-<nom du modèle>`, et il faut
lancer l'installation avec `-Modele <nom>`. Sans dossier correspondant,
le modèle est simplement téléchargé comme avant.

### Et pour whisper.cpp

Copie le dossier `C:\whisper-cpp` de ta machine dans la clé, sous le nom
`whisper-cpp`. S'il est présent, le script le copie au lieu de le
télécharger, et ne pose plus la question.

Avec ces deux dossiers sur la clé, **seuls Python et ffmpeg peuvent
encore exiger Internet** — et uniquement s'ils manquent sur la machine.

---

## Désinstaller

Double-clic sur **`DESINSTALLER.bat`**, depuis la clé ou depuis le
dossier d'installation — l'installeur y dépose une copie du
désinstalleur, c'est là qu'on le cherchera le jour venu.

Lancé depuis le dossier d'installation, il ouvre sa propre fenêtre et
rend la main aussitôt : il va supprimer le fichier qu'il est en train
d'exécuter. Le compte rendu final arrive dans une boîte de dialogue,
succès comme échec.

Le script retrouve l'installation tout seul : d'abord le dossier où il se
trouve, puis la cible du raccourci du Bureau, puis les emplacements
habituels. Il affiche un inventaire, demande confirmation, et supprime le
dossier d'installation, l'environnement Python, les modèles installés et
le raccourci du Bureau.

**Les enregistrements et les transcriptions sont traités à part.** Ce
sont des données de séance, pas des fichiers de programme :

- une **copie de sauvegarde** est proposée avant toute suppression ;
- sans réponse explicite, **elles sont conservées** — le dossier
  d'installation est vidé mais `enregistrements\` et `transcriptions\`
  restent en place ;
- si le `.ini` les a déplacées ailleurs, ce sont les vrais chemins qui
  sont lus, pas ceux qu'on suppose.

Le raccourci du Bureau n'est retiré que s'il pointe vers l'installation
qu'on retire. Une seconde installation ailleurs garde le sien.

Les modèles du cache Hugging Face (`%USERPROFILE%\.cache\huggingface`)
sont conservés par défaut : ce cache est partagé, Handy y range aussi les
siens, et les garder évite de tout retélécharger en cas de réinstallation.
Une question permet de les supprimer.

**Python et ffmpeg ne sont jamais touchés** — d'autres logiciels peuvent
en dépendre. Pour les retirer aussi, à la main :

```powershell
winget uninstall Gyan.FFmpeg
winget uninstall Python.Python.3.12
```

### Voir ce qui serait supprimé, sans rien supprimer

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Desinstaller-Transcription.ps1 -Simuler
```

Depuis le dossier d'installation, où le script est posé à plat, c'est
`.\Desinstaller-Transcription.ps1 -Simuler`.

---

## Si ça coince

**« Ecriture impossible »** — l'emplacement choisi demande les droits
administrateur. Deux issues : clic droit sur `INSTALLER.bat` › « Exécuter
en tant qu'administrateur », ou choisir un dossier dans le profil
utilisateur, par exemple `C:\Users\<toi>\TRANS_CRIPTION_AUDIO`.

**« Python installé mais introuvable »** — le PATH de la fenêtre en cours
date d'avant l'installation. Ferme-la, rouvre `INSTALLER.bat`, ça repart
de là où c'en était.

**Aucun micro dans la liste** — ffmpeg vient d'être installé et Windows
n'a pas encore diffusé le nouveau PATH. Ferme la session Windows et
rouvre-la.

**Ni Python ni winget sur la machine** — installe Python depuis
python.org en cochant « Add Python to PATH », puis relance.

---

## Options en ligne de commande

Pour se passer des fenêtres, par exemple pour équiper plusieurs postes
identiques :

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Installer-Transcription.ps1 `
    -Destination "C:\TRANS_CRIPTION_AUDIO" `
    -Modele small `
    -AvecWhisperCpp `
    -SansQuestions
```

Les options passées à `INSTALLER.bat` ou `DESINSTALLER.bat` sont
transmises telles quelles au script : `INSTALLER.bat -Modele small`
fonctionne aussi.

| Option de l'installeur | Effet |
|---|---|
| `-Destination` | chemin complet ; supprime la fenêtre de navigation |
| `-Modele` | `large-v3` (défaut), `medium`, `small`, `base` |
| `-AvecWhisperCpp` | installe le second moteur sans poser la question |
| `-SansRaccourci` | pas de raccourci sur le Bureau |
| `-SansQuestions` | aucune fenêtre ; les questions non tranchées sont refusées |

| Option du désinstalleur | Effet |
|---|---|
| `-Destination` | l'installation à retirer ; sinon elle est cherchée |
| `-Simuler` | affiche le bilan et s'arrête, sans rien supprimer |
| `-GarderDonnees` | conserve enregistrements et transcriptions |
| `-EffacerDonnees` | les supprime avec le reste, sans demander |
| `-SupprimerModeles` | vide aussi le cache Hugging Face |
| `-SansQuestions` | aucune fenêtre ; les données sont conservées par défaut |
