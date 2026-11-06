#!/usr/bin/env python3
# -*- coding: utf-8 -*-
r"""
transcription_gui.py - enregistrement et transcription de seance

Deux boutons, deux temoins lumineux :
  - Enregistrer / Arreter  (ffmpeg en tache de fond)
  - Transcrire             (faster-whisper, modele garde en memoire)

Les temoins ne changent pas de couleur "a l'aveugle" : le vert n'apparait
qu'apres verification que le fichier existe reellement sur le disque,
qu'il n'est plus en cours d'ecriture et qu'il n'est pas vide.

Configuration : transcription.ini, cree au premier lancement a cote de
ce script. Les chemins des dossiers y sont modifiables.

Lancement :
    $py = "$env:USERPROFILE\wlk\.venv\Scripts\python.exe"
    & $py transcription_gui.py
"""

import configparser
import os
import queue
import re
import subprocess
import sys
import threading
import time
from datetime import datetime
from pathlib import Path

import tkinter as tk
from tkinter import ttk, filedialog, messagebox
from tkinter.scrolledtext import ScrolledText

ICI = Path(__file__).resolve().parent
INI = ICI / "transcription.ini"

EXTENSIONS_AUDIO = {".wav", ".m4a", ".mp3", ".flac", ".ogg", ".opus", ".mp4"}

# Evite qu'une fenetre console noire clignote a chaque appel ffmpeg.
SANS_FENETRE = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0

# Etats des temoins lumineux
GRIS   = ("#9e9e9e", "#616161")   # inactif, rien a signaler
ROUGE  = ("#e53935", "#b71c1c")   # traitement en cours
ORANGE = ("#fb8c00", "#e65100")   # finalisation / verification du fichier
VERT   = ("#43a047", "#1b5e20")   # fichier verifie, disponible
NOIR   = ("#37474f", "#263238")   # erreur


# =============================================================
#  Configuration
# =============================================================

DEFAUTS = {
    "chemins": {
        "dossier_audio": str(ICI / "enregistrements"),
        "dossier_texte": str(ICI / "transcriptions"),
    },
    "audio": {
        "micro": "",
        "frequence": "16000",
        "canaux": "1",
    },
    "transcription": {
        # faster-whisper : moteur Python, deja installe, tres bonne qualite
        # whisper-cpp    : executable autonome (le moteur de Handy),
        #                  plus rapide, aucune dependance Python
        "moteur": "faster-whisper",
        "modele": "large-v3",
        "langue": "fr",
        "beam": "5",
        "threads": "8",
        "vad": "non",
        "prompt": (
            "Consultation dentaire. Vocabulaire : composite, inlay-core, "
            "couronne ceramo-metallique, endodontie, pulpite, articaine "
            "adrenalinee, curetage sous-gingival, detartrage, surfacage, "
            "carie, mobilite, devis, dent 16, dent 26, dent 36, dent 46."
        ),
    },
    "whisper_cpp": {
        # Chemin complet vers whisper-cli.exe (ou main.exe selon la version)
        "executable": "",
        # Chemin complet vers le fichier modele .bin (format ggml)
        "modele": "",
        "threads": "8",
    },
    "options": {
        # oui = l'audio est supprime des que la transcription a reussi.
        # A passer a oui des qu'il s'agit de vraies seances.
        "effacer_audio_apres_transcription": "non",
    },
}


# Emplacements ou l'on cherche whisper.cpp tout seul, dans l'ordre.
# Les archives officielles rangent les binaires dans un sous-dossier
# "Release" ; d'autres versions les posent a la racine.
CANDIDATS_WHISPER_CPP = [
    Path(r"C:\whisper-cpp\Release\whisper-cli.exe"),
    Path(r"C:\whisper-cpp\whisper-cli.exe"),
    Path(r"C:\whisper-cpp\Release\main.exe"),
    Path(r"C:\whisper-cpp\main.exe"),
    ICI / "whisper-cpp" / "Release" / "whisper-cli.exe",
    ICI / "whisper-cpp" / "whisper-cli.exe",
]


def completer_whisper_cpp(cfg):
    """Renseigne [whisper_cpp] quand l'utilisateur ne l'a pas fait.

    Sans cela, basculer sur le moteur de Handy depuis l'interface
    obligerait a editer le .ini a la main. Une valeur deja presente
    n'est jamais remplacee : un chemin choisi reste prioritaire.

    Renvoie True si quelque chose a ete ecrit.
    """
    modifie = False

    if not cfg["whisper_cpp"]["executable"].strip():
        for c in CANDIDATS_WHISPER_CPP:
            if c.exists():
                cfg.set("whisper_cpp", "executable", str(c))
                modifie = True
                break

    if not cfg["whisper_cpp"]["modele"].strip():
        dossiers = [Path(r"C:\whisper-cpp\models"),
                    ICI / "whisper-cpp" / "models"]
        exe = cfg["whisper_cpp"]["executable"].strip()
        if exe:
            # Le dossier des modeles est frere de celui des binaires,
            # ou son oncle quand l'archive garde son sous-dossier Release.
            dossiers.insert(0, Path(exe).parent / "models")
            dossiers.insert(1, Path(exe).parent.parent / "models")
        for d in dossiers:
            if not d.is_dir():
                continue
            bins = sorted(d.glob("ggml-*.bin"))
            if not bins:
                continue
            # Les modeles "turbo" quantifies sont le compromis
            # vitesse/qualite de Handy : on les prefere s'ils sont la.
            turbo = [b for b in bins if "turbo" in b.name]
            cfg.set("whisper_cpp", "modele", str((turbo or bins)[0]))
            modifie = True
            break

    return modifie


def charger_config():
    # Le prompt contient des ':' -> pas d'interpolation, sinon ConfigParser
    # tente de resoudre des variables inexistantes.
    cfg = configparser.ConfigParser(interpolation=None)
    if INI.exists():
        cfg.read(INI, encoding="utf-8")

    modifie = False
    for section, valeurs in DEFAUTS.items():
        if not cfg.has_section(section):
            cfg.add_section(section)
            modifie = True
        for cle, val in valeurs.items():
            if not cfg.has_option(section, cle):
                cfg.set(section, cle, val)
                modifie = True

    if completer_whisper_cpp(cfg):
        modifie = True

    if modifie:
        sauver_config(cfg)
    return cfg


def sauver_config(cfg):
    with open(INI, "w", encoding="utf-8") as f:
        cfg.write(f)


# =============================================================
#  Detection des micros
# =============================================================

def lister_micros():
    """Interroge ffmpeg pour les peripheriques DirectShow audio.

    Renvoie (liste_micros, sortie_brute). Deux formats sont geres :
      - ffmpeg recent (>= 7) : chaque ligne porte "Nom" (audio) ou (video)
      - ffmpeg ancien        : sections "DirectShow audio devices"
    """
    if sys.platform != "win32":
        return [], "Plateforme non Windows."
    try:
        p = subprocess.run(
            ["ffmpeg", "-hide_banner", "-list_devices", "true",
             "-f", "dshow", "-i", "dummy"],
            capture_output=True, text=True,
            encoding="utf-8", errors="replace",
            timeout=20, creationflags=SANS_FENETRE,
        )
    except FileNotFoundError:
        return [], "ffmpeg est introuvable dans le PATH."
    except Exception as e:
        return [], f"Echec de l'appel a ffmpeg : {e}"

    # ffmpeg ecrit la liste sur stderr et sort en erreur : c'est normal.
    sortie = (p.stderr or "") + (p.stdout or "")
    micros = []

    # --- format recent : ... "Nom du micro" (audio) ---
    # Le nom peut lui-meme contenir des parentheses, d'ou [^"]+ entre
    # guillemets plutot qu'une expression plus fine.
    for ligne in sortie.splitlines():
        if "Alternative name" in ligne:
            continue
        m = re.search(r'"([^"]+)"\s*\((audio|video)\)', ligne)
        if m and m.group(2) == "audio" and m.group(1) not in micros:
            micros.append(m.group(1))

    # --- repli : format ancien, par sections ---
    if not micros:
        dans_audio = False
        for ligne in sortie.splitlines():
            if "DirectShow video devices" in ligne:
                dans_audio = False
                continue
            if "DirectShow audio devices" in ligne:
                dans_audio = True
                continue
            if not dans_audio or "Alternative name" in ligne:
                continue
            m = re.search(r'"([^"]+)"', ligne)
            if m and "@device" not in m.group(1) and m.group(1) not in micros:
                micros.append(m.group(1))

    return micros, sortie


# =============================================================
#  Verification qu'un fichier est reellement disponible
# =============================================================

def attendre_fichier_stable(chemin: Path, taille_mini=1024,
                            delai_max=20.0, pas=0.25):
    """Attend qu'un fichier soit ecrit ET termine.

    L'existence seule ne suffit pas : ffmpeg cree le .wav des le debut de
    l'enregistrement et continue d'y ecrire. On considere le fichier
    disponible quand sa taille cesse de bouger sur deux relectures
    consecutives et qu'il depasse une taille plancher.

    Renvoie (True, taille) ou (False, message d'erreur).
    """
    debut = time.time()
    precedente = -1
    stables = 0

    while time.time() - debut < delai_max:
        if chemin.exists():
            try:
                taille = chemin.stat().st_size
            except OSError:
                taille = -1
            if taille == precedente and taille >= taille_mini:
                stables += 1
                if stables >= 2:
                    return True, taille
            else:
                stables = 0
            precedente = taille
        time.sleep(pas)

    if not chemin.exists():
        return False, "Le fichier n'a jamais ete cree."
    return False, f"Fichier incomplet ou vide ({chemin.stat().st_size} octets)."


# =============================================================
#  Temoin lumineux
# =============================================================

class Temoin(ttk.Frame):
    """Pastille coloree + libelle + detail. Clignote en etat 'en cours'."""

    def __init__(self, parent, libelle):
        super().__init__(parent)
        self.canvas = tk.Canvas(self, width=20, height=20,
                                highlightthickness=0, bd=0)
        self.canvas.pack(side="left")
        self.pastille = self.canvas.create_oval(
            4, 4, 17, 17, fill=GRIS[0], outline=GRIS[1], width=2)

        ttk.Label(self, text=libelle, width=13,
                  font=("Segoe UI", 9, "bold")).pack(side="left", padx=(6, 4))
        self.detail = ttk.Label(self, text="-", foreground="#555",
                                font=("Segoe UI", 9))
        self.detail.pack(side="left")

        self._couleurs = GRIS
        self._clignote = False
        self._allume = True

    def regler(self, couleurs, detail=None, clignote=False):
        self._couleurs = couleurs
        self._clignote = clignote
        self._allume = True
        self.canvas.itemconfig(self.pastille,
                               fill=couleurs[0], outline=couleurs[1])
        if detail is not None:
            self.detail.config(text=detail)
        if clignote:
            self._battre()

    def _battre(self):
        if not self._clignote:
            self.canvas.itemconfig(self.pastille, fill=self._couleurs[0])
            return
        self._allume = not self._allume
        self.canvas.itemconfig(
            self.pastille,
            fill=self._couleurs[0] if self._allume else "#ffffff")
        self.after(450, self._battre)


# =============================================================
#  Application
# =============================================================

class Application(tk.Tk):

    def __init__(self):
        super().__init__()
        self.title("Transcription de seance")
        self.geometry("900x720")
        self.minsize(760, 560)

        self.cfg = charger_config()
        self.dossier_audio = Path(self.cfg["chemins"]["dossier_audio"])
        self.dossier_texte = Path(self.cfg["chemins"]["dossier_texte"])
        self.dossier_audio.mkdir(parents=True, exist_ok=True)
        self.dossier_texte.mkdir(parents=True, exist_ok=True)

        self.proc_ffmpeg = None
        self.fichier_en_cours = None
        self.fichier_choisi = None
        self.debut_enreg = None
        self.modele = None          # charge une seule fois, garde en memoire
        self.messages = queue.Queue()

        self._construire()
        self._maj_libelle_moteur()
        self._rafraichir_micros()
        self._maj_fichier_cible()
        self.after(120, self._vider_file)
        self.protocol("WM_DELETE_WINDOW", self._fermer)

    # ---------------------------------------------------------
    # Interface
    # ---------------------------------------------------------
    def _construire(self):
        haut = ttk.Frame(self, padding=10)
        haut.pack(fill="x")

        # --- micro ---
        l1 = ttk.Frame(haut); l1.pack(fill="x", pady=(0, 8))
        ttk.Label(l1, text="Micro :", width=8).pack(side="left")
        self.combo_micro = ttk.Combobox(l1, state="readonly")
        self.combo_micro.pack(side="left", fill="x", expand=True, padx=(0, 6))
        self.combo_micro.bind("<<ComboboxSelected>>", self._micro_choisi)
        ttk.Button(l1, text="Detecter", width=10,
                   command=self._rafraichir_micros).pack(side="left")

        # --- moteur ---
        lm = ttk.Frame(haut); lm.pack(fill="x", pady=(0, 8))
        ttk.Label(lm, text="Moteur :", width=8).pack(side="left")
        actuel = self.cfg["transcription"]["moteur"].strip().lower()
        self.var_moteur = tk.StringVar(
            value="whisper-cpp" if actuel == "whisper-cpp"
            else "faster-whisper")
        ttk.Radiobutton(lm, text="faster-whisper", value="faster-whisper",
                        variable=self.var_moteur,
                        command=self._moteur_choisi).pack(side="left")
        ttk.Radiobutton(lm, text="whisper.cpp (Handy)", value="whisper-cpp",
                        variable=self.var_moteur,
                        command=self._moteur_choisi).pack(side="left",
                                                          padx=(12, 0))
        self.lbl_moteur = ttk.Label(lm, text="", foreground="#555",
                                    font=("Segoe UI", 8))
        self.lbl_moteur.pack(side="left", padx=(14, 0))

        # --- boutons ---
        l2 = ttk.Frame(haut); l2.pack(fill="x", pady=(0, 10))
        self.btn_enreg = tk.Button(
            l2, text="  Enregistrer  ", command=self._basculer_enregistrement,
            font=("Segoe UI", 11, "bold"), bg="#2e7d32", fg="white",
            activebackground="#1b5e20", activeforeground="white",
            relief="flat", padx=16, pady=10, cursor="hand2")
        self.btn_enreg.pack(side="left", padx=(0, 8))

        self.btn_transcrire = tk.Button(
            l2, text="  Transcrire  ", command=self._lancer_transcription,
            font=("Segoe UI", 11, "bold"), bg="#1565c0", fg="white",
            activebackground="#0d47a1", activeforeground="white",
            relief="flat", padx=16, pady=10, cursor="hand2")
        self.btn_transcrire.pack(side="left", padx=(0, 8))

        ttk.Button(l2, text="Choisir un fichier...",
                   command=self._choisir_fichier).pack(side="left", padx=(0, 8))
        self.lbl_chrono = ttk.Label(l2, text="", font=("Consolas", 14))
        self.lbl_chrono.pack(side="left", padx=10)

        # --- temoins ---
        cadre_t = ttk.LabelFrame(haut, text="Etat des fichiers", padding=8)
        cadre_t.pack(fill="x", pady=(0, 8))

        self.temoin_audio = Temoin(cadre_t, "Audio")
        self.temoin_audio.pack(fill="x", pady=2)
        self.temoin_texte = Temoin(cadre_t, "Transcription")
        self.temoin_texte.pack(fill="x", pady=2)

        legende = ("gris = rien   |   rouge clignotant = traitement en cours   |   "
                   "orange = verification du fichier   |   vert = disponible")
        ttk.Label(cadre_t, text=legende, foreground="#777",
                  font=("Segoe UI", 8)).pack(fill="x", pady=(6, 0))

        # --- dossiers ---
        cadre_d = ttk.Frame(haut); cadre_d.pack(fill="x")
        for libelle, dossier in (("Audio", self.dossier_audio),
                                 ("Texte", self.dossier_texte)):
            ligne = ttk.Frame(cadre_d); ligne.pack(fill="x", pady=1)
            ttk.Label(ligne, text=f"{libelle} :", width=8).pack(side="left")
            ttk.Label(ligne, text=str(dossier), foreground="#1565c0",
                      font=("Consolas", 8)).pack(side="left",
                                                 fill="x", expand=True)
            ttk.Button(ligne, text="Ouvrir", width=8,
                       command=lambda d=dossier: self._ouvrir_dossier(d)
                       ).pack(side="left")

        # --- fichier cible ---
        self.lbl_cible = ttk.Label(haut, text="", foreground="#555")
        self.lbl_cible.pack(fill="x", pady=(6, 0))

        # --- zone de texte ---
        cadre = ttk.LabelFrame(self, text="Transcription", padding=6)
        cadre.pack(fill="both", expand=True, padx=10, pady=(4, 6))
        self.texte = ScrolledText(cadre, wrap="word",
                                  font=("Segoe UI", 11), undo=True)
        self.texte.pack(fill="both", expand=True)

        # --- bas ---
        bas = ttk.Frame(self, padding=(10, 0, 10, 8)); bas.pack(fill="x")
        ttk.Button(bas, text="Copier", command=self._copier).pack(side="left")
        ttk.Button(bas, text="Enregistrer le texte",
                   command=self._sauver_texte).pack(side="left", padx=6)
        ttk.Button(bas, text="Effacer",
                   command=lambda: self.texte.delete("1.0", "end")).pack(side="left")

        self.lbl_statut = ttk.Label(self, text="Pret.", relief="sunken",
                                    anchor="w", padding=(8, 4))
        self.lbl_statut.pack(fill="x", side="bottom")

    def _ouvrir_dossier(self, dossier: Path):
        dossier.mkdir(parents=True, exist_ok=True)
        try:
            if sys.platform == "win32":
                os.startfile(str(dossier))
            else:
                subprocess.Popen(["xdg-open", str(dossier)])
        except Exception as e:
            messagebox.showerror("Dossier", str(e))

    # ---------------------------------------------------------
    # Micros
    # ---------------------------------------------------------
    def _rafraichir_micros(self):
        self._statut("Detection des peripheriques audio...")
        self.update_idletasks()

        micros, brut = lister_micros()
        self.combo_micro["values"] = micros

        enregistre = self.cfg["audio"]["micro"]
        if enregistre and enregistre in micros:
            self.combo_micro.set(enregistre)
        elif micros:
            self.combo_micro.set(micros[0])
        else:
            self.combo_micro.set("")

        if micros:
            self._statut(f"{len(micros)} micro(s) detecte(s).")
        else:
            # Sans cet affichage, un echec de detection est muet et
            # impossible a diagnostiquer depuis l'interface.
            self._statut("Aucun micro detecte - voir la sortie ffmpeg ci-dessous.")
            self.texte.delete("1.0", "end")
            self.texte.insert("1.0", "Sortie brute de ffmpeg :\n\n" + brut)

    def _micro_choisi(self, _evt=None):
        self.cfg["audio"]["micro"] = self.combo_micro.get()
        sauver_config(self.cfg)

    # ---------------------------------------------------------
    # Moteur de transcription
    # ---------------------------------------------------------
    def _moteur_choisi(self):
        """Bascule faster-whisper <-> whisper.cpp sans redemarrage.

        Le moteur est relu dans la config a chaque transcription :
        ecrire le .ini et rafraichir le libelle suffit.
        """
        self.cfg["transcription"]["moteur"] = self.var_moteur.get()
        sauver_config(self.cfg)
        self._maj_libelle_moteur()

    def _maj_libelle_moteur(self):
        """Affiche ce que le moteur choisi va reellement utiliser.

        En whisper.cpp, un chemin manquant se voit ici, tout de suite,
        plutot qu'au milieu d'une transcription ratee.
        """
        if self.var_moteur.get() == "whisper-cpp":
            w = self.cfg["whisper_cpp"]
            exe = Path(w["executable"]) if w["executable"].strip() else None
            mod = Path(w["modele"]) if w["modele"].strip() else None
            if not exe or not exe.exists():
                self.lbl_moteur.config(
                    text="whisper-cli.exe introuvable "
                         "- section [whisper_cpp] du .ini",
                    foreground="#c62828")
            elif not mod or not mod.exists():
                self.lbl_moteur.config(
                    text="modele .bin introuvable "
                         "- section [whisper_cpp] du .ini",
                    foreground="#c62828")
            else:
                self.lbl_moteur.config(
                    text="%s  (%s threads)" % (mod.name, w["threads"]),
                    foreground="#555")
            self._statut("Moteur : whisper.cpp, celui de Handy.")
        else:
            t = self.cfg["transcription"]
            # Le modele est soit un nom court que faster-whisper
            # telechargera (large-v3), soit un dossier complet quand il a
            # ete installe depuis une cle USB. Dans ce cas on n'affiche
            # que le nom du dossier : le chemin entier deborderait.
            nom = t["modele"]
            if "\\" in nom or "/" in nom:
                nom = Path(nom).name
            self.lbl_moteur.config(
                text="modele %s, CPU int8 (%s threads)" % (nom, t["threads"]),
                foreground="#555")
            self._statut("Moteur : faster-whisper.")

    # ---------------------------------------------------------
    # Enregistrement
    # ---------------------------------------------------------
    def _basculer_enregistrement(self):
        if self.proc_ffmpeg is None:
            self._demarrer_enregistrement()
        else:
            self._arreter_enregistrement()

    def _demarrer_enregistrement(self):
        micro = self.combo_micro.get()
        if not micro:
            messagebox.showerror("Micro", "Aucun micro selectionne.")
            return

        horodatage = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
        cible = self.dossier_audio / f"{horodatage}.wav"

        # Le nom du peripherique peut contenir des parentheses et des
        # espaces : comme on passe une liste (pas de shell), aucune
        # protection de guillemets n'est necessaire ici.
        cmd = [
            "ffmpeg", "-hide_banner", "-loglevel", "error",
            "-f", "dshow", "-i", f"audio={micro}",
            "-ac", self.cfg["audio"]["canaux"],
            "-ar", self.cfg["audio"]["frequence"],
            "-c:a", "pcm_s16le", "-y", str(cible),
        ]

        try:
            # stdin ouvert : on y enverra 'q' pour un arret propre.
            # Un kill brutal laisserait un WAV a l'en-tete incomplet.
            self.proc_ffmpeg = subprocess.Popen(
                cmd, stdin=subprocess.PIPE,
                stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                creationflags=SANS_FENETRE,
            )
        except FileNotFoundError:
            messagebox.showerror("ffmpeg", "ffmpeg est introuvable dans le PATH.")
            return

        self.fichier_en_cours = cible
        self.debut_enreg = time.time()
        self.btn_enreg.config(text="  Arreter  ", bg="#c62828",
                              activebackground="#8e0000")
        self.btn_transcrire.config(state="disabled")
        self.temoin_audio.regler(ROUGE, "enregistrement en cours...",
                                 clignote=True)
        self.temoin_texte.regler(GRIS, "-")
        self._statut(f"Enregistrement -> {cible.name}")
        self._tic()

    def _tic(self):
        if self.proc_ffmpeg is None:
            self.lbl_chrono.config(text="")
            return
        e = int(time.time() - self.debut_enreg)
        self.lbl_chrono.config(text=f"{e // 60:02d}:{e % 60:02d}",
                               foreground="#c62828")
        self.after(500, self._tic)

    def _arreter_enregistrement(self):
        p = self.proc_ffmpeg
        self.proc_ffmpeg = None
        self.lbl_chrono.config(text="")
        self.btn_enreg.config(text="  Enregistrer  ", bg="#2e7d32",
                              activebackground="#1b5e20", state="disabled")
        self.temoin_audio.regler(ORANGE, "finalisation du fichier...",
                                 clignote=True)
        self._statut("Fermeture du fichier audio...")

        cible = self.fichier_en_cours
        # La fermeture de ffmpeg et la verification prennent un instant :
        # dans un thread, sinon l'interface se fige et le temoin ne
        # clignote pas.
        threading.Thread(target=self._finir_enregistrement,
                         args=(p, cible), daemon=True).start()

    def _finir_enregistrement(self, p, cible: Path):
        erreur = b""
        try:
            p.stdin.write(b"q")
            p.stdin.flush()
            p.stdin.close()
        except Exception:
            pass
        try:
            p.wait(timeout=8)
        except subprocess.TimeoutExpired:
            p.kill()
        try:
            erreur = p.stderr.read() or b""
        except Exception:
            pass

        ok, info = attendre_fichier_stable(cible)

        if ok:
            mo = info / (1024 * 1024)
            self.messages.put(("temoin_audio",
                               (VERT, f"{cible.name}  ({mo:.1f} Mo)", False)))
            self.messages.put(("statut", f"Audio disponible : {cible}"))
        else:
            msg = erreur.decode("utf-8", "replace").strip()
            self.messages.put(("temoin_audio", (NOIR, str(info), False)))
            self.messages.put(("erreur",
                               "Aucun son n'a ete capture.\n\n" + str(info) +
                               "\n\nVerifie le micro et l'autorisation Windows "
                               "(Parametres > Confidentialite > Microphone > "
                               "'Autoriser les applications de bureau').\n\n"
                               + msg[:600]))
        self.messages.put(("fin_enregistrement", None))

    # ---------------------------------------------------------
    # Choix du fichier
    # ---------------------------------------------------------
    def _dernier_audio(self):
        if not self.dossier_audio.exists():
            return None
        f = [x for x in self.dossier_audio.iterdir()
             if x.is_file() and x.suffix.lower() in EXTENSIONS_AUDIO]
        return max(f, key=lambda x: x.stat().st_mtime) if f else None

    def _maj_fichier_cible(self):
        f = self.fichier_choisi or self._dernier_audio()
        if f:
            marque = "choisi" if self.fichier_choisi else "le plus recent"
            self.lbl_cible.config(text=f"A transcrire : {f.name}  ({marque})")
        else:
            self.lbl_cible.config(text="Aucun fichier audio disponible.")

    def _choisir_fichier(self):
        chemin = filedialog.askopenfilename(
            title="Choisir un fichier audio",
            initialdir=str(self.dossier_audio),
            filetypes=[("Fichiers audio", "*.wav *.m4a *.mp3 *.flac *.ogg *.opus"),
                       ("Tous les fichiers", "*.*")])
        if chemin:
            self.fichier_choisi = Path(chemin)
            self._maj_fichier_cible()

    # ---------------------------------------------------------
    # Transcription
    # ---------------------------------------------------------
    def _lancer_transcription(self):
        cible = self.fichier_choisi or self._dernier_audio()
        if not cible or not cible.exists():
            messagebox.showwarning("Transcription",
                                   "Aucun fichier audio a transcrire.")
            return

        self.btn_transcrire.config(state="disabled")
        self.btn_enreg.config(state="disabled")
        self.texte.delete("1.0", "end")
        self.temoin_texte.regler(ROUGE, "transcription en cours...",
                                 clignote=True)
        self._statut(f"Transcription de {cible.name}...")

        # Thread : sans cela l'interface se figerait pendant tout le calcul.
        threading.Thread(target=self._travail_transcription,
                         args=(cible,), daemon=True).start()

    def _travail_transcription(self, cible: Path):
        t = self.cfg["transcription"]

        # Le moteur est teste AVANT l'import : whisper.cpp doit rester
        # utilisable dans un environnement ou faster-whisper manque.
        if t.get("moteur", "faster-whisper").strip().lower() == "whisper-cpp":
            self._transcrire_whisper_cpp(cible)
            return

        try:
            from faster_whisper import WhisperModel
        except ImportError:
            self.messages.put(("temoin_texte",
                               (NOIR, "faster-whisper absent", False)))
            self.messages.put(("erreur",
                               "faster-whisper n'est pas installe dans cet "
                               "environnement Python."))
            self.messages.put(("fin_transcription", None))
            return

        try:
            if self.modele is None:
                self.messages.put(("temoin_texte",
                                   (ROUGE, f"chargement du modele "
                                           f"{t['modele']}...", True)))
                t0 = time.time()
                self.modele = WhisperModel(
                    t["modele"], device="cpu", compute_type="int8",
                    cpu_threads=int(t["threads"]))
                self.messages.put(("statut",
                                   f"Modele charge en {time.time()-t0:.1f} s "
                                   f"(garde en memoire pour la suite)."))

            self.messages.put(("temoin_texte",
                               (ROUGE, "decodage en cours...", True)))
            t1 = time.time()
            segments, info = self.modele.transcribe(
                str(cible),
                language=t["langue"],
                beam_size=int(t["beam"]),
                initial_prompt=t["prompt"] or None,
                vad_filter=(t["vad"].strip().lower()
                            in ("oui", "yes", "true", "1")),
                condition_on_previous_text=False,
            )

            morceaux = []
            for seg in segments:
                txt = seg.text.strip()
                morceaux.append(txt)
                # Affichage au fil de l'eau : l'utilisateur voit que ca avance.
                self.messages.put(("texte", txt + " "))

            duree = time.time() - t1
            texte = " ".join(morceaux).strip()

            self.messages.put(("temoin_texte",
                               (ORANGE, "ecriture du fichier...", True)))
            sortie = self.dossier_texte / (cible.stem + ".txt")
            sortie.write_text(texte + "\n", encoding="utf-8")

            ok, info_f = attendre_fichier_stable(sortie, taille_mini=1,
                                                 delai_max=10)
            if ok:
                facteur = duree / info.duration if info.duration else 0
                self.messages.put((
                    "temoin_texte",
                    (VERT, f"{sortie.name}  ({info_f} octets)", False)))
                self.messages.put((
                    "statut",
                    f"Termine - audio {info.duration:.0f} s, calcul "
                    f"{duree:.0f} s ({facteur:.2f}x) - {sortie}"))
            else:
                self.messages.put(("temoin_texte", (NOIR, str(info_f), False)))

            if self.cfg["options"]["effacer_audio_apres_transcription"] \
                    .strip().lower() in ("oui", "yes", "true", "1"):
                try:
                    cible.unlink()
                    self.messages.put(("temoin_audio",
                                       (GRIS, "audio supprime "
                                              "(texte conserve)", False)))
                except OSError:
                    pass

        except Exception as e:
            self.messages.put(("temoin_texte",
                               (NOIR, type(e).__name__, False)))
            self.messages.put(("erreur", f"{type(e).__name__} : {e}"))
        finally:
            self.messages.put(("fin_transcription", None))

    def _transcrire_whisper_cpp(self, cible: Path):
        """Transcription via l'executable whisper.cpp / transcribe.cpp.

        C'est le moteur qu'utilise Handy : inference ggml en C++, sans
        aucune dependance Python. Il attend un WAV 16 kHz mono, ce que
        produit deja notre enregistreur - aucune conversion necessaire.
        """
        w = self.cfg["whisper_cpp"]
        exe = Path(w["executable"]) if w["executable"] else None
        mod = Path(w["modele"]) if w["modele"] else None

        if not exe or not exe.exists():
            self.messages.put(("temoin_texte", (NOIR, "executable introuvable", False)))
            self.messages.put(("erreur",
                               "whisper-cli.exe est introuvable.\n\n"
                               "Renseigne [whisper_cpp] executable dans "
                               "transcription.ini."))
            self.messages.put(("fin_transcription", None))
            return
        if not mod or not mod.exists():
            self.messages.put(("temoin_texte", (NOIR, "modele introuvable", False)))
            self.messages.put(("erreur",
                               "Le fichier modele .bin est introuvable.\n\n"
                               "Renseigne [whisper_cpp] modele dans "
                               "transcription.ini."))
            self.messages.put(("fin_transcription", None))
            return

        t = self.cfg["transcription"]
        sortie = self.dossier_texte / cible.stem
        cmd = [
            str(exe),
            "-m", str(mod),
            "-f", str(cible),
            "-l", t["langue"],
            "-t", w["threads"],
            "-otxt", "-of", str(sortie),
        ]
        if t["prompt"]:
            cmd += ["--prompt", t["prompt"]]

        self.messages.put(("temoin_texte", (ROUGE, "decodage (whisper.cpp)...", True)))
        t0 = time.time()

        try:
            proc = subprocess.Popen(
                cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, encoding="utf-8", errors="replace",
                bufsize=1, creationflags=SANS_FENETRE)

            # whisper.cpp ecrit ses segments au fil de l'eau, sous la forme
            # [00:00:00.000 --> 00:00:04.000]   texte
            motif = re.compile(r"^\[[\d:.]+ --> [\d:.]+\]\s*(.*)$")
            for ligne in proc.stdout:
                m = motif.match(ligne.strip())
                if m and m.group(1):
                    self.messages.put(("texte", m.group(1).strip() + " "))
            proc.wait()

            duree = time.time() - t0
            fichier = sortie.with_suffix(".txt")
            ok, info_f = attendre_fichier_stable(fichier, taille_mini=1,
                                                 delai_max=10)
            if ok:
                self.messages.put((
                    "temoin_texte",
                    (VERT, f"{fichier.name}  ({info_f} octets)", False)))
                self.messages.put((
                    "statut",
                    f"Termine (whisper.cpp) en {duree:.0f} s - {fichier}"))
            else:
                self.messages.put(("temoin_texte", (NOIR, str(info_f), False)))
                self.messages.put(("erreur",
                                   f"whisper.cpp n'a produit aucun texte.\n\n{info_f}"))

            if self.cfg["options"]["effacer_audio_apres_transcription"] \
                    .strip().lower() in ("oui", "yes", "true", "1"):
                try:
                    cible.unlink()
                    self.messages.put(("temoin_audio",
                                       (GRIS, "audio supprime (texte conserve)",
                                        False)))
                except OSError:
                    pass

        except Exception as e:
            self.messages.put(("temoin_texte", (NOIR, type(e).__name__, False)))
            self.messages.put(("erreur", f"{type(e).__name__} : {e}"))
        finally:
            self.messages.put(("fin_transcription", None))

    # ---------------------------------------------------------
    # Pont thread -> interface
    # ---------------------------------------------------------
    def _vider_file(self):
        try:
            while True:
                genre, charge = self.messages.get_nowait()

                if genre == "texte":
                    self.texte.insert("end", charge)
                    self.texte.see("end")
                elif genre == "statut":
                    self._statut(charge)
                elif genre == "temoin_audio":
                    couleurs, detail, clignote = charge
                    self.temoin_audio.regler(couleurs, detail, clignote)
                elif genre == "temoin_texte":
                    couleurs, detail, clignote = charge
                    self.temoin_texte.regler(couleurs, detail, clignote)
                elif genre == "erreur":
                    self._statut("Erreur.")
                    messagebox.showerror("Erreur", charge)
                elif genre == "fin_enregistrement":
                    self.btn_enreg.config(state="normal")
                    self.btn_transcrire.config(state="normal")
                    self._maj_fichier_cible()
                elif genre == "fin_transcription":
                    self.btn_transcrire.config(state="normal")
                    self.btn_enreg.config(state="normal")
                    self._maj_fichier_cible()
        except queue.Empty:
            pass
        self.after(120, self._vider_file)

    # ---------------------------------------------------------
    # Divers
    # ---------------------------------------------------------
    def _statut(self, msg):
        self.lbl_statut.config(text=msg)

    def _copier(self):
        self.clipboard_clear()
        self.clipboard_append(self.texte.get("1.0", "end-1c"))
        self._statut("Texte copie dans le presse-papiers.")

    def _sauver_texte(self):
        chemin = filedialog.asksaveasfilename(
            defaultextension=".txt", initialdir=str(self.dossier_texte),
            filetypes=[("Texte", "*.txt")])
        if chemin:
            Path(chemin).write_text(self.texte.get("1.0", "end-1c"),
                                    encoding="utf-8")
            self._statut(f"Enregistre : {Path(chemin).name}")

    def _fermer(self):
        if self.proc_ffmpeg is not None:
            if not messagebox.askyesno(
                    "Enregistrement en cours",
                    "Un enregistrement est en cours. Quitter quand meme ?"):
                return
            self._arreter_enregistrement()
            time.sleep(1.0)
        self.destroy()


if __name__ == "__main__":
    Application().mainloop()
