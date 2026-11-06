# =============================================================
#  Desinstallation de l'application de transcription de seance
#
#  Retire le dossier d'installation, son environnement Python, ses
#  modeles et le raccourci du Bureau.
#
#  Les enregistrements et les transcriptions sont traites a part : ce
#  sont des donnees de seance, pas des fichiers de programme. Rien ne
#  les efface sans une reponse explicite, et une sauvegarde est
#  proposee avant.
#
#  Lancement : double-clic sur DESINSTALLER.bat, a la racine de la cle
#  ou dans le dossier d'installation.
#
#  Pour voir ce qui serait supprime sans rien toucher :
#    powershell -ExecutionPolicy Bypass -File .\scripts\Desinstaller-Transcription.ps1 -Simuler
#
#  (depuis une installation, le script est a plat : .\Desinstaller-Transcription.ps1)
# =============================================================

param(
    # Vide = on cherche l'installation tout seul.
    [string]$Destination = "",
    # Conserve enregistrements\ et transcriptions\ sans poser la question.
    [switch]$GarderDonnees,
    # Les supprime avec le reste. Sans l'un ni l'autre, la question est
    # posee, et l'absence de reponse vaut conservation.
    [switch]$EffacerDonnees,
    # Retire aussi les modeles du cache Hugging Face (partage).
    [switch]$SupprimerModeles,
    # Montre le bilan et s'arrete : rien n'est supprime.
    [switch]$Simuler,
    [switch]$SansQuestions,
    # Usage interne : le script s'est recopie dans TEMP pour pouvoir
    # supprimer le dossier depuis lequel il tournait.
    [switch]$DepuisTemp
)

$ErrorActionPreference = "Stop"
$Source = $PSScriptRoot
if (-not $Source) { $Source = Split-Path -Parent $MyInvocation.MyCommand.Path }

$NomDossier = "TRANS_CRIPTION_AUDIO"
$NomRaccourci = "Transcription de seance.lnk"

# Ne jamais avoir pour dossier courant celui qu'on va supprimer :
# Windows refuse d'effacer un dossier qu'un processus utilise comme tel,
# et la suppression echouerait a mi-chemin. Set-Location ne suffit pas,
# le dossier courant natif du processus est une autre variable.
Set-Location $env:TEMP
[Environment]::CurrentDirectory = $env:TEMP

Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()


# -------------------------------------------------------------
#  Utilitaires
# -------------------------------------------------------------
function Titre($texte) {
    Write-Host ""
    Write-Host "===============================================" -ForegroundColor Cyan
    Write-Host "  $texte" -ForegroundColor Cyan
    Write-Host "===============================================" -ForegroundColor Cyan
}

function Bien($texte)  { Write-Host "      $texte" -ForegroundColor Green }
function Info($texte)  { Write-Host "      $texte" -ForegroundColor DarkGray }
function Souci($texte) { Write-Host "      $texte" -ForegroundColor Red }

function Demander($question, $titre) {
    if ($SansQuestions) { return $false }
    $r = [System.Windows.Forms.MessageBox]::Show(
        $question, $titre,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question)
    return ($r -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Arreter($message) {
    Souci $message
    if (-not $SansQuestions) {
        [System.Windows.Forms.MessageBox]::Show(
            $message, "Desinstallation interrompue",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
    exit 1
}

function Taille($chemin) {
    if (-not (Test-Path $chemin)) { return 0 }
    $s = (Get-ChildItem $chemin -Recurse -File -ErrorAction SilentlyContinue |
          Measure-Object Length -Sum).Sum
    if ($s) { return $s } else { return 0 }
}

function EstUneInstallation($chemin, $souple = $false) {
    if (-not $chemin -or -not (Test-Path $chemin)) { return $false }

    # Un dossier qui sait installer est un kit, pas une installation :
    # le confondre reviendrait, lance depuis la cle USB, a effacer la
    # cle. Les trois dispositions possibles du kit sont ecartees.
    foreach ($signe in @("INSTALLER.bat",
                         "Installer-Transcription.ps1",
                         "scripts\Installer-Transcription.ps1")) {
        if (Test-Path (Join-Path $chemin $signe)) { return $false }
    }

    # Ce qui signe une installation, c'est ce que l'installeur a
    # fabrique sur place : l'environnement Python et le lanceur.
    if ((Test-Path (Join-Path $chemin ".venv")) -or
        (Test-Path (Join-Path $chemin "Lancer.bat"))) { return $true }

    # Une desinstallation qui a conserve les seances laisse un dossier
    # sans programme. Le reconnaitre permet d'y revenir pour le vider,
    # mais seulement s'il a ete designe explicitement : jamais par la
    # recherche automatique, qui pourrait tomber sur n'importe quoi.
    if ($souple) {
        return (Test-Path (Join-Path $chemin "enregistrements")) -or
               (Test-Path (Join-Path $chemin "transcriptions"))
    }
    return $false
}


# -------------------------------------------------------------
#  1. Retrouver l'installation
# -------------------------------------------------------------
Titre "Desinstallation - Transcription de seance"
if ($Simuler) { Write-Host "  MODE SIMULATION : rien ne sera supprime." -ForegroundColor Magenta }

# Un dossier designe a la main merite plus de confiance que celui qu'on
# a devine : lui seul peut n'etre qu'un reliquat de donnees.
$designeALaMain = [bool]$Destination

if (-not $Destination) {
    $pistes = @()

    # a) Le script est peut-etre pose dans l'installation elle-meme.
    if (EstUneInstallation $Source) { $pistes += $Source }

    # b) Le raccourci du Bureau sait ou pointe l'application.
    $lnk = Join-Path ([Environment]::GetFolderPath("Desktop")) $NomRaccourci
    if (Test-Path $lnk) {
        try {
            $sh = New-Object -ComObject WScript.Shell
            $pistes += $sh.CreateShortcut($lnk).WorkingDirectory
        } catch { }
    }

    # c) Les emplacements habituels.
    $pistes += "C:\$NomDossier"
    $pistes += (Join-Path $env:USERPROFILE $NomDossier)

    foreach ($p in $pistes) {
        if (EstUneInstallation $p) { $Destination = $p; break }
    }
}

if (-not (EstUneInstallation $Destination $designeALaMain)) {
    if ($SansQuestions) {
        Arreter "Aucune installation trouvee. Indique-la avec -Destination."
    }
    # Derniere chance : que l'utilisateur la designe lui-meme.
    [System.Windows.Forms.MessageBox]::Show(
        "L'installation n'a pas ete trouvee automatiquement.`n`nIndique le dossier dans la fenetre suivante.",
        "Dossier introuvable",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null

    $nav = New-Object System.Windows.Forms.FolderBrowserDialog
    $nav.Description = "Designe le dossier $NomDossier a desinstaller."
    $nav.SelectedPath = "C:\"
    if ($nav.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $Destination = $nav.SelectedPath
    }
    if (-not (EstUneInstallation $Destination $true)) {
        Arreter "Ce dossier ne contient pas d'installation (ni .venv, ni Lancer.bat).`n`nRien n'a ete supprime."
    }
}

Write-Host "  Installation : $Destination"


# -------------------------------------------------------------
#  2. Inventaire
# -------------------------------------------------------------
Write-Host ""
Write-Host "[1/4] Inventaire..." -ForegroundColor Yellow

$dossierAudio = Join-Path $Destination "enregistrements"
$dossierTexte = Join-Path $Destination "transcriptions"

# Le .ini peut deplacer ces dossiers hors de l'installation : on lit
# les chemins reels plutot que de les supposer.
$ini = Join-Path $Destination "transcription.ini"
if (Test-Path $ini) {
    $contenu = Get-Content $ini -Raw -Encoding UTF8
    if ($contenu -match "dossier_audio\s*=\s*(.+)") { $dossierAudio = $Matches[1].Trim() }
    if ($contenu -match "dossier_texte\s*=\s*(.+)") { $dossierTexte = $Matches[1].Trim() }
}

$audios = @()
$textes = @()
if (Test-Path $dossierAudio) { $audios = @(Get-ChildItem $dossierAudio -File -ErrorAction SilentlyContinue) }
if (Test-Path $dossierTexte) { $textes = @(Get-ChildItem $dossierTexte -File -ErrorAction SilentlyContinue) }

$totalInstall = Taille $Destination
Info ("Dossier complet      : {0:N2} Go" -f ($totalInstall / 1GB))
Info ("Enregistrements      : {0} fichier(s), {1:N2} Go" -f $audios.Count, ((Taille $dossierAudio) / 1GB))
Info ("Transcriptions       : {0} fichier(s)" -f $textes.Count)

# Le raccourci n'est retire que s'il mene bien a CETTE installation :
# une seconde installation ailleurs garde le sien.
$lnkBureau = Join-Path ([Environment]::GetFolderPath("Desktop")) $NomRaccourci
$raccourciANous = $false
if (Test-Path $lnkBureau) {
    try {
        $sh = New-Object -ComObject WScript.Shell
        $r = $sh.CreateShortcut($lnkBureau)
        $vise = ($r.TargetPath + " " + $r.Arguments + " " + $r.WorkingDirectory).ToLower()
        $raccourciANous = $vise.Contains($Destination.TrimEnd('\').ToLower())
    } catch { }
    if ($raccourciANous) { Info "Raccourci du Bureau  : present" }
    else { Info "Raccourci du Bureau  : pointe ailleurs, il sera conserve" }
}

# Modeles du cache Hugging Face. Attention : ce cache est partage. Handy
# y range aussi les siens, on ne touche qu'aux modeles faster-whisper.
$hub = Join-Path $env:USERPROFILE ".cache\huggingface\hub"
$modelesFW = @()
if (Test-Path $hub) {
    $modelesFW = @(Get-ChildItem $hub -Directory -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -like "*faster-whisper*" })
}
$tailleModeles = 0
foreach ($m in $modelesFW) { $tailleModeles += (Taille $m.FullName) }
if ($modelesFW.Count) {
    Info ("Cache Hugging Face   : {0} modele(s) faster-whisper, {1:N2} Go" -f $modelesFW.Count, ($tailleModeles / 1GB))
}


# -------------------------------------------------------------
#  3. Le sort des donnees de seance
# -------------------------------------------------------------
Write-Host ""
Write-Host "[2/4] Enregistrements et transcriptions..." -ForegroundColor Yellow

$donnees = $audios.Count + $textes.Count

if ($donnees -eq 0) {
    Info "Aucune donnee de seance : rien a preserver."
} elseif ($EffacerDonnees) {
    Info "Donnees supprimees avec le reste (choix deja confirme)."
} elseif ($GarderDonnees) {
    Info "Donnees conservees (option -GarderDonnees)."
} elseif ($SansQuestions -or $Simuler) {
    # Sans personne pour repondre, on ne detruit pas des seances.
    Info "Aucune question possible : les donnees sont conservees par precaution."
    $GarderDonnees = $true
} else {
    $sauver = Demander (
        "Cette installation contient $($audios.Count) enregistrement(s) " +
        "et $($textes.Count) transcription(s).`n`n" +
        "En faire une copie de sauvegarde avant de continuer ?") "Donnees de seance"

    if ($sauver) {
        $nav = New-Object System.Windows.Forms.FolderBrowserDialog
        $nav.Description = "Ou deposer la sauvegarde des seances ?"
        $nav.SelectedPath = [Environment]::GetFolderPath("Desktop")
        if ($nav.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $sauvegarde = Join-Path $nav.SelectedPath ("Transcription-donnees-" + (Get-Date -Format "yyyy-MM-dd"))
            New-Item -ItemType Directory -Force -Path $sauvegarde | Out-Null
            if ($audios.Count) {
                New-Item -ItemType Directory -Force -Path (Join-Path $sauvegarde "enregistrements") | Out-Null
                Copy-Item "$dossierAudio\*" (Join-Path $sauvegarde "enregistrements") -Recurse -Force
            }
            if ($textes.Count) {
                New-Item -ItemType Directory -Force -Path (Join-Path $sauvegarde "transcriptions") | Out-Null
                Copy-Item "$dossierTexte\*" (Join-Path $sauvegarde "transcriptions") -Recurse -Force
            }
            Bien "Sauvegarde : $sauvegarde"
            $EffacerDonnees = Demander (
                "Sauvegarde faite dans :`n$sauvegarde`n`n" +
                "Supprimer maintenant les donnees d'origine ?") "Donnees de seance"
        } else {
            Info "Sauvegarde annulee : les donnees seront conservees."
        }
    } else {
        $EffacerDonnees = Demander (
            "Aucune sauvegarde ne sera faite.`n`n" +
            "Supprimer definitivement les $donnees fichier(s) de seance ?`n`n" +
            "Cette action est irreversible.") "Suppression definitive"
    }

    if (-not $EffacerDonnees) { $GarderDonnees = $true }
}

# La question des modeles est posee ici, avant toute suppression : si le
# script doit se relancer depuis TEMP, il lui faut deja la reponse.
if ($modelesFW.Count -and -not $SupprimerModeles -and -not $SansQuestions -and
    -not $DepuisTemp -and -not $Simuler) {
    $SupprimerModeles = Demander (
        ("Supprimer aussi les modeles telecharges ?`n`n" +
         "{0:N2} Go dans le cache Hugging Face.`n`n" +
         "A garder si tu comptes reinstaller : ils seraient sinon " +
         "a retelecharger.") -f ($tailleModeles / 1GB)) "Modeles telecharges"
}


# -------------------------------------------------------------
#  4. Confirmation
# -------------------------------------------------------------
$resume = "Va etre supprime :`n`n" +
          "  $Destination`n" +
          ("  ({0:N2} Go : application, environnement Python, modeles)`n" -f ($totalInstall / 1GB))
if ($raccourciANous) { $resume += "  Le raccourci du Bureau`n" }
if ($GarderDonnees -and $donnees -gt 0) {
    $resume += "`nSeront CONSERVES :`n  $dossierAudio`n  $dossierTexte`n"
} elseif ($donnees -gt 0) {
    $resume += "`nY COMPRIS les $donnees fichier(s) de seance.`n"
}
if ($SupprimerModeles -and $modelesFW.Count) {
    $resume += ("`nEt les modeles du cache Hugging Face ({0:N2} Go).`n" -f ($tailleModeles / 1GB))
}
$resume += "`nPython et ffmpeg ne sont pas touches.`n`nContinuer ?"

if ($Simuler) {
    Write-Host ""
    Write-Host ($resume -replace "`nContinuer \?", "")
    Write-Host ""
    Write-Host "  Simulation : rien n'a ete supprime." -ForegroundColor Magenta
    exit 0
}

if (-not $SansQuestions -and -not $DepuisTemp) {
    $ok = [System.Windows.Forms.MessageBox]::Show(
        $resume, "Confirmation",
        [System.Windows.Forms.MessageBoxButtons]::OKCancel,
        [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($ok -ne [System.Windows.Forms.DialogResult]::OK) {
        Write-Host "`nDesinstallation annulee. Rien n'a ete supprime." -ForegroundColor Yellow
        exit 0
    }
} else {
    Write-Host $resume
}


# -------------------------------------------------------------
#  5. Le script se met a l'abri s'il est dans ce qu'il supprime
# -------------------------------------------------------------
$dansLaCible = $Source.TrimEnd('\').ToLower().StartsWith($Destination.TrimEnd('\').ToLower())

if ($dansLaCible -and -not $DepuisTemp) {
    # PowerShell garde la main sur le fichier en cours d'execution :
    # on se recopie dans TEMP et on repart de la.
    $abri = Join-Path $env:TEMP ("desinstall-transcription-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $abri | Out-Null
    Copy-Item $MyInvocation.MyCommand.Path $abri -Force
    $copie = Join-Path $abri (Split-Path $MyInvocation.MyCommand.Path -Leaf)

    Write-Host ""
    Info "Le script se relance depuis un dossier temporaire."

    # Toutes les decisions deja prises sont transmises : le second
    # passage ne repose aucune question, mais affiche encore le bilan.
    $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$copie`"",
                   "-Destination", "`"$Destination`"", "-DepuisTemp")
    if ($GarderDonnees)    { $arguments += "-GarderDonnees" }
    if ($EffacerDonnees)   { $arguments += "-EffacerDonnees" }
    if ($SupprimerModeles) { $arguments += "-SupprimerModeles" }
    if ($SansQuestions)    { $arguments += "-SansQuestions" }

    Start-Process -FilePath "powershell" -ArgumentList $arguments `
                  -WorkingDirectory $env:TEMP -Wait
    exit 0
}


# -------------------------------------------------------------
#  6. Suppression
# -------------------------------------------------------------
Write-Host ""
Write-Host "[3/4] Suppression..." -ForegroundColor Yellow

if ($raccourciANous -and (Test-Path $lnkBureau)) {
    Remove-Item $lnkBureau -Force
    Bien "Raccourci du Bureau retire"
}

# Les donnees a conserver sont mises de cote avant que le dossier parent
# ne disparaisse, puis reposees a leur place.
$refuge = $null
if ($GarderDonnees -and $donnees -gt 0) {
    $dansInstall = $dossierAudio.ToLower().StartsWith($Destination.TrimEnd('\').ToLower()) -or
                   $dossierTexte.ToLower().StartsWith($Destination.TrimEnd('\').ToLower())
    if ($dansInstall) {
        $refuge = Join-Path $env:TEMP ("donnees-transcription-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
        New-Item -ItemType Directory -Force -Path $refuge | Out-Null
        if (Test-Path $dossierAudio) { Copy-Item $dossierAudio $refuge -Recurse -Force }
        if (Test-Path $dossierTexte) { Copy-Item $dossierTexte $refuge -Recurse -Force }
        Info "Donnees mises de cote le temps de la suppression."
    }
}

try {
    Remove-Item $Destination -Recurse -Force
    Bien "Dossier d'installation supprime"
} catch {
    # Une suppression qui echoue a mi-chemin a pu emporter les donnees
    # deja mises de cote : on les repose avant de s'arreter, sinon
    # l'echec se solderait par une perte.
    $secours = ""
    if ($refuge) {
        try {
            New-Item -ItemType Directory -Force -Path $Destination | Out-Null
            Get-ChildItem $refuge -Directory | ForEach-Object {
                Copy-Item $_.FullName $Destination -Recurse -Force
            }
            Remove-Item $refuge -Recurse -Force
            $secours = "`n`nLes enregistrements et transcriptions ont ete remis en place."
        } catch {
            $secours = "`n`nLes donnees sont en lieu sur dans :`n$refuge"
        }
    }
    Arreter "Impossible de supprimer $Destination.`n`n$_`n`nFerme l'application si elle est ouverte, puis recommence.$secours"
}

if ($refuge) {
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Get-ChildItem $refuge -Directory | ForEach-Object {
        Copy-Item $_.FullName $Destination -Recurse -Force
    }
    Remove-Item $refuge -Recurse -Force
    Bien "Donnees de seance replacees dans $Destination"
}

Write-Host ""
Write-Host "[4/4] Cache des modeles..." -ForegroundColor Yellow

if ($modelesFW.Count -eq 0) {
    Info "Aucun modele faster-whisper dans le cache."
} else {
    if ($SupprimerModeles) {
        foreach ($m in $modelesFW) {
            Remove-Item $m.FullName -Recurse -Force -ErrorAction SilentlyContinue
            Info "supprime : $($m.Name)"
        }
        Bien ("Cache libere : {0:N2} Go" -f ($tailleModeles / 1GB))
    } else {
        Info "Modeles conserves dans $hub"
    }
}


# -------------------------------------------------------------
#  Fin
# -------------------------------------------------------------
Titre "Desinstallation terminee"
Write-Host ""
if ($GarderDonnees -and $donnees -gt 0) {
    Write-Host "  Donnees conservees : $Destination" -ForegroundColor Green
}
Write-Host "  Python et ffmpeg sont restes en place. Pour les retirer aussi :" -ForegroundColor DarkGray
Write-Host "    winget uninstall Gyan.FFmpeg" -ForegroundColor DarkGray
Write-Host "    winget uninstall Python.Python.3.12" -ForegroundColor DarkGray
Write-Host ""

if (-not $SansQuestions) {
    [System.Windows.Forms.MessageBox]::Show(
        "Desinstallation terminee.", "Termine",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}
