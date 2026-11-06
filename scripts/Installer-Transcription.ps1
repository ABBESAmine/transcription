# =============================================================
#  Installation de l'application de transcription de seance
#  Version "cle USB" : autonome, utilisable sur un PC neuf.
#
#  Difference avec installer.ps1 : l'emplacement se choisit dans une
#  fenetre de navigation, et les prerequis manquants (Python, ffmpeg)
#  sont installes au lieu de faire echouer le script.
#
#  Lancement : double-clic sur INSTALLER.bat, a la racine de la cle.
#
#  Ou, en ligne de commande, pour se passer des fenetres :
#    powershell -ExecutionPolicy Bypass -File .\scripts\Installer-Transcription.ps1 `
#               -Destination "D:\Transcription" -Modele small -AvecWhisperCpp
#
#  Disposition attendue de la cle :
#    INSTALLER.bat  DESINSTALLER.bat  LISEZ-MOI.md
#    scripts\      les deux scripts
#    application\  transcription_gui.py
#    modeles\      faster-whisper-<modele>\   (facultatif)
#    whisper-cpp\  le second moteur           (facultatif)
# =============================================================

param(
    # Vide = la fenetre de navigation s'ouvre, avec C:\ comme depart.
    [string]$Destination = "",
    [ValidateSet("large-v3", "medium", "small", "base")]
    [string]$Modele = "large-v3",
    [switch]$SansRaccourci,
    # Installe aussi le moteur de Handy. Sans ce commutateur, la
    # question est posee a l'ecran.
    [switch]$AvecWhisperCpp,
    # Aucune fenetre, aucune question : pour un deploiement en serie
    # ou un test automatise. Demande -Destination.
    [switch]$SansQuestions
)

$ErrorActionPreference = "Stop"
$Source = $PSScriptRoot
if (-not $Source) { $Source = Split-Path -Parent $MyInvocation.MyCommand.Path }

# Sur la cle, ce script vit dans scripts\ et tout le reste est range a
# cote : application\, modeles\, whisper-cpp\. La racine du kit est donc
# le dossier au-dessus. Pose a plat, il reste sa propre racine.
$Racine = $Source
if ((Split-Path $Source -Leaf) -eq "scripts") { $Racine = Split-Path -Parent $Source }

$NomDossier = "TRANS_CRIPTION_AUDIO"
$ParDefaut = "C:\$NomDossier"

# Sources de telechargement. La version de whisper.cpp est figee : une
# version connue vaut mieux qu'une derniere version non testee.
$WhisperCppTag = "b4938"
$WhisperCppUrl = "https://github.com/ggml-org/whisper.cpp/releases/download/$WhisperCppTag/whisper-bin-x64.zip"
$WhisperCppModele = "ggml-large-v3-turbo-q5_0.bin"
$WhisperCppModeleUrl = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$WhisperCppModele"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()


# -------------------------------------------------------------
#  Petits utilitaires d'affichage
# -------------------------------------------------------------
function Titre($texte) {
    Write-Host ""
    Write-Host "===============================================" -ForegroundColor Cyan
    Write-Host "  $texte" -ForegroundColor Cyan
    Write-Host "===============================================" -ForegroundColor Cyan
}

function Etape($n, $texte) {
    Write-Host ""
    Write-Host "[$n/8] $texte" -ForegroundColor Yellow
}

function Bien($texte)  { Write-Host "      $texte" -ForegroundColor Green }
function Info($texte)  { Write-Host "      $texte" -ForegroundColor DarkGray }
function Souci($texte) { Write-Host "      $texte" -ForegroundColor Red }

function Demander($question, $titre) {
    # En mode silencieux, toute question non tranchee par un parametre
    # se resout par la reponse la plus prudente : non.
    if ($SansQuestions) { return $false }
    $r = [System.Windows.Forms.MessageBox]::Show(
        $question, $titre,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question)
    return ($r -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Arreter($message) {
    Souci($message)
    if (-not $SansQuestions) {
        [System.Windows.Forms.MessageBox]::Show(
            $message, "Installation interrompue",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
    exit 1
}


# -------------------------------------------------------------
#  0. L'application est-elle a cote du script ?
# -------------------------------------------------------------
Titre "Installation - Transcription de seance"
Write-Host "  Source : $Racine"

# L'application est dans application\ sur la cle ; a la racine si le kit
# a ete remis a plat.
$appli = Join-Path $Racine "application\transcription_gui.py"
if (-not (Test-Path $appli)) { $appli = Join-Path $Racine "transcription_gui.py" }
if (-not (Test-Path $appli)) {
    Arreter "transcription_gui.py est introuvable.`n`nAttendu dans $Racine\application\ ou dans $Racine."
}


# -------------------------------------------------------------
#  1. Ou installer ?
# -------------------------------------------------------------
Etape 1 "Emplacement de l'installation..."

if (-not $Destination -and $SansQuestions) {
    $Destination = $ParDefaut
    Info "Mode silencieux : emplacement par defaut."
}

if (-not $Destination) {
    $nav = New-Object System.Windows.Forms.FolderBrowserDialog
    $nav.Description = "Choisis l'emplacement de l'installation.`r`n" +
                       "Un dossier $NomDossier y sera cree.`r`n`r`n" +
                       "Par defaut : $ParDefaut"
    $nav.ShowNewFolderButton = $true
    $nav.SelectedPath = "C:\"

    if ($nav.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $choisi = $nav.SelectedPath
        # Si l'utilisateur designe deja un dossier TRANS_CRIPTION_AUDIO,
        # on installe dedans plutot que d'en imbriquer un second.
        if ((Split-Path $choisi -Leaf) -eq $NomDossier) {
            $Destination = $choisi
        } else {
            $Destination = Join-Path $choisi $NomDossier
        }
    } else {
        $Destination = $ParDefaut
        Info "Navigation annulee : emplacement par defaut retenu."
    }
}

Write-Host "      $Destination" -ForegroundColor White

# Installer par-dessus la cle elle-meme melangerait sources et
# installation, et le desinstalleur ne saurait plus les distinguer.
if ($Destination.TrimEnd('\').ToLower() -eq $Racine.TrimEnd('\').ToLower()) {
    Arreter "L'installation ne peut pas se faire dans le dossier du kit lui-meme.`n`nChoisis un autre emplacement."
}


# -------------------------------------------------------------
#  2. Machine cible, et adaptation du modele
# -------------------------------------------------------------
Etape 2 "Machine cible..."
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$coeurs = $cpu.NumberOfLogicalProcessors
$ram = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
Info $cpu.Name.Trim()
Info "$coeurs coeurs logiques, $ram Go de RAM"

if ($ram -lt 8 -and $Modele -eq "large-v3") {
    Souci "Moins de 8 Go de RAM pour un modele large-v3."
    if (Demander "Cette machine a $ram Go de RAM. Le modele large-v3 y sera lent et pourra saturer la memoire.`n`nInstaller le modele 'small' a la place ?" "Modele trop lourd") {
        $Modele = "small"
        Bien "Modele ramene a 'small'."
    }
}

# Le nombre de threads suit la machine : garder 8 sur un PC a 4 coeurs
# ferait travailler le moteur contre lui-meme.
$threads = [math]::Max(2, [math]::Min($coeurs, 8))


# -------------------------------------------------------------
#  3. whisper.cpp : sur la cle, a telecharger, ou pas du tout ?
# -------------------------------------------------------------
Etape 3 "Moteur whisper.cpp (celui de Handy)..."

$cppSurLaCle = Join-Path $Racine "whisper-cpp"
$posercpp = $false
$copiercpp = $false

if (Test-Path $cppSurLaCle) {
    Info "Present sur la cle : il sera copie, sans telechargement."
    $posercpp = $true
    $copiercpp = $true
} elseif ($AvecWhisperCpp) {
    $posercpp = $true
} else {
    $posercpp = Demander (
        "Installer aussi le second moteur, whisper.cpp ?`n`n" +
        "C'est le moteur utilise par Handy. L'application permet de " +
        "basculer de l'un a l'autre d'un clic.`n`n" +
        "Telechargement supplementaire : environ 560 Mo.") "Second moteur"
}
if ($posercpp) { Bien "whisper.cpp : oui" } else { Info "whisper.cpp : non" }


# -------------------------------------------------------------
#  4. Recapitulatif avant d'ecrire quoi que ce soit
# -------------------------------------------------------------
$recap = "Destination :`n$Destination`n`n" +
         "Modele faster-whisper : $Modele`n" +
         "Threads : $threads`n" +
         "Second moteur whisper.cpp : $(if ($posercpp) {'oui'} else {'non'})`n" +
         "Raccourci sur le Bureau : $(if ($SansRaccourci) {'non'} else {'oui'})`n`n" +
         "Lancer l'installation ?"

if (-not $SansQuestions) {
    $ok = [System.Windows.Forms.MessageBox]::Show(
        $recap, "Recapitulatif",
        [System.Windows.Forms.MessageBoxButtons]::OKCancel,
        [System.Windows.Forms.MessageBoxIcon]::Information)
    if ($ok -ne [System.Windows.Forms.DialogResult]::OK) {
        Write-Host "`nInstallation annulee." -ForegroundColor Yellow
        exit 0
    }
} else {
    Write-Host ($recap -replace "Lancer l'installation \?", "")
}


# -------------------------------------------------------------
#  5. Prerequis : Python et ffmpeg
# -------------------------------------------------------------
Etape 4 "Python..."

function Trouver-Python {
    <#
      Renvoie le chemin d'un python.exe en version 3.9 a 3.13, ou $null.
      On interroge le lanceur "py" et le PATH, puis on va voir dans les
      emplacements d'installation habituels : apres une installation
      toute fraiche, le PATH du processus courant est encore l'ancien.
    #>
    $ErrorActionPreference = "SilentlyContinue"
    $candidats = @()

    # Le lanceur "py" sait lister ce qui est installe. L'interroger une
    # seule fois evite d'essayer chaque version l'une apres l'autre :
    # celles qui manquent afficheraient un message d'erreur inquietant
    # au milieu d'une installation qui se passe bien.
    try {
        foreach ($ligne in (& py -0p)) {
            if ($ligne -match '-V:\d+\.\d+\S*\s+\*?\s*(.+\.exe)\s*$') {
                $candidats += $Matches[1].Trim()
            }
        }
    } catch { }

    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd) { $candidats += $cmd.Source }

    foreach ($racine in @("$env:LOCALAPPDATA\Programs\Python",
                          "$env:ProgramFiles\Python313",
                          "$env:ProgramFiles\Python312",
                          "$env:ProgramFiles\Python311")) {
        if (Test-Path $racine) {
            $candidats += (Get-ChildItem $racine -Filter "python.exe" -Recurse -Depth 1 -ErrorAction SilentlyContinue).FullName
        }
    }

    # Les "python.exe" de WindowsApps sont des amorces qui ouvrent le
    # Microsoft Store au lieu de repondre : on les ecarte.
    $candidats = $candidats | Where-Object { $_ -and $_ -notlike "*\WindowsApps\*" } |
                 Select-Object -Unique

    $valides = @()
    foreach ($c in $candidats) {
        try {
            $v = & $c -c "import sys; print('%d.%d' % sys.version_info[:2])"
            if ($v -match '^3\.(9|10|11|12|13)$') {
                $valides += [PSCustomObject]@{ Chemin = $c; Version = [version]$v }
            }
        } catch { }
    }
    if ($valides.Count) {
        # La plus recente des versions utilisables, quel que soit
        # l'ordre dans lequel on les a trouvees.
        return ($valides | Sort-Object Version -Descending | Select-Object -First 1).Chemin
    }
    return $null
}

$python = Trouver-Python
if ($python) {
    $ver = & $python -c "import sys; print('%d.%d.%d' % sys.version_info[:3])"
    Bien "Python $ver - $python"
} else {
    Info "Absent. Installation de Python 3.12 par winget..."
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Arreter "Ni Python (3.9 a 3.13) ni winget ne sont disponibles sur cette machine.`n`nInstalle Python depuis python.org en cochant 'Add Python to PATH', puis relance ce script."
    }
    winget install --id Python.Python.3.12 -e --scope user --accept-source-agreements --accept-package-agreements --disable-interactivity
    $python = Trouver-Python
    if (-not $python) {
        Arreter "Python a ete installe mais reste introuvable.`n`nFerme cette fenetre, ouvres-en une nouvelle, et relance l'installation."
    }
    Bien "Python installe - $python"
}

Etape 5 "ffmpeg..."

function Trouver-Ffmpeg {
    $cmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    # winget range ffmpeg dans un dossier de paquet dont le nom porte
    # le numero de version : on cherche plutot que de le deviner.
    foreach ($racine in @("$env:LOCALAPPDATA\Microsoft\WinGet\Packages",
                          "$env:ProgramFiles\ffmpeg")) {
        if (Test-Path $racine) {
            $f = Get-ChildItem $racine -Filter "ffmpeg.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($f) { return $f.FullName }
        }
    }
    return $null
}

$ffmpeg = Trouver-Ffmpeg
if (-not $ffmpeg) {
    Info "Absent. Installation par winget..."
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Arreter "Ni ffmpeg ni winget ne sont disponibles.`n`nInstalle ffmpeg depuis https://www.gyan.dev/ffmpeg/builds/ et ajoute son dossier bin au PATH, puis relance ce script."
    }
    winget install --id Gyan.FFmpeg -e --scope user --accept-source-agreements --accept-package-agreements --disable-interactivity
    $ffmpeg = Trouver-Ffmpeg
    if (-not $ffmpeg) {
        Arreter "ffmpeg a ete installe mais reste introuvable.`n`nFerme cette fenetre, ouvres-en une nouvelle, et relance l'installation."
    }
}
Bien "ffmpeg - $ffmpeg"

# L'application appelle "ffmpeg" tout court : il lui faut le PATH. Une
# installation toute fraiche n'a pas encore atteint les processus en
# cours, d'ou cette mise a jour explicite, pour cette fenetre et pour
# les suivantes.
$dossierFfmpeg = Split-Path $ffmpeg -Parent
$pathUtilisateur = [Environment]::GetEnvironmentVariable("Path", "User")
if ($pathUtilisateur -notlike "*$dossierFfmpeg*") {
    [Environment]::SetEnvironmentVariable("Path", "$pathUtilisateur;$dossierFfmpeg", "User")
    Info "Dossier de ffmpeg ajoute au PATH."
}
$env:Path = "$env:Path;$dossierFfmpeg"


# -------------------------------------------------------------
#  6. Dossiers et fichiers
# -------------------------------------------------------------
Etape 6 "Dossiers et fichiers..."

try {
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    # La creation d'un dossier peut reussir la ou l'ecriture d'un
    # fichier sera refusee : on teste ce qui compte vraiment.
    $t = Join-Path $Destination ".test"
    Set-Content -Path $t -Value "x" -ErrorAction Stop
    Remove-Item $t -Force
} catch {
    Arreter "Ecriture impossible dans $Destination.`n`nCet emplacement demande les droits administrateur. Relance en tant qu'administrateur, ou choisis un dossier dans ton profil utilisateur, par exemple $env:USERPROFILE\$NomDossier."
}

New-Item -ItemType Directory -Force -Path (Join-Path $Destination "enregistrements") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Destination "transcriptions") | Out-Null

Copy-Item $appli $Destination -Force
Info "transcription_gui.py"

# Le desinstalleur est depose dans l'installation : c'est la qu'on le
# cherchera, pas sur une cle rangee depuis longtemps. Il y est pose a
# plat, et le .bat sait chercher le .ps1 a cote de lui.
foreach ($f in @("$Source\Desinstaller-Transcription.ps1",
                 "$Racine\DESINSTALLER.bat",
                 "$Racine\INSTALLATION.md",
                 "$Racine\TUTO-INSTALLATION.md",
                 "$Racine\texte-reference.txt",
                 "$Racine\termes-cibles.txt")) {
    if (Test-Path $f) {
        Copy-Item $f $Destination -Force
        Info (Split-Path $f -Leaf)
    }
}

# Le .ini n'est jamais copie depuis la cle : il contient les chemins
# absolus de la machine d'origine. Celui qui existerait deja ici est
# conserve, mais ses chemins sont verifies.
$ini = Join-Path $Destination "transcription.ini"
if (Test-Path $ini) {
    $contenu = Get-Content $ini -Raw -Encoding UTF8
    if ($contenu -match "dossier_audio\s*=\s*(.+)") {
        $ancien = $Matches[1].Trim()
        if (-not (Test-Path (Split-Path $ancien -Parent))) {
            Info "transcription.ini existant : chemins obsoletes, remis a jour."
            $contenu = $contenu -replace "dossier_audio\s*=.*", "dossier_audio = $Destination\enregistrements"
            $contenu = $contenu -replace "dossier_texte\s*=.*", "dossier_texte = $Destination\transcriptions"
            Set-Content -Path $ini -Value $contenu -Encoding UTF8
        } else {
            Info "transcription.ini existant conserve."
        }
    }
}


# -------------------------------------------------------------
#  7. Environnement Python dedie et moteur
# -------------------------------------------------------------
Etape 7 "Environnement Python dedie..."
$venv = Join-Path $Destination ".venv"
if (Test-Path (Join-Path $venv "Scripts\python.exe")) {
    Info "Environnement existant reutilise."
} else {
    & $python -m venv $venv
}
$py = Join-Path $venv "Scripts\python.exe"
if (-not (Test-Path $py)) { Arreter "La creation de l'environnement Python a echoue." }

& $py -m pip install --upgrade pip --quiet
Info "Installation de faster-whisper (quelques minutes)..."
# av<19 : PyAV 19 a supprime le parametre metadata_errors que
# faster-whisper 1.2.x passe a av.open(). Sans ce plafond, toute
# transcription echoue avec "unexpected keyword argument 'metadata_errors'".
& $py -m pip install faster-whisper "av<19"
if ($LASTEXITCODE -ne 0) { Arreter "L'installation de faster-whisper a echoue. Verifie la connexion Internet." }
Bien "faster-whisper installe"

# Le modele peut voyager sur la cle. faster-whisper accepte aussi bien
# un nom court ("large-v3", qu'il telecharge) qu'un dossier complet :
# c'est ce qui permet une installation sans Internet.
$modeleSurLaCle = Join-Path $Racine "modeles\faster-whisper-$Modele"
$ModeleIni = $Modele

if (Test-Path $modeleSurLaCle) {
    $dossierModeles = Join-Path $Destination "modeles"
    New-Item -ItemType Directory -Force -Path $dossierModeles | Out-Null
    $ModeleIni = Join-Path $dossierModeles "faster-whisper-$Modele"
    $taille = (Get-ChildItem $modeleSurLaCle -Recurse -File | Measure-Object Length -Sum).Sum
    Info ("Modele '$Modele' present sur la cle : copie de {0:N1} Go, sans telechargement..." -f ($taille / 1GB))
    Copy-Item $modeleSurLaCle $dossierModeles -Recurse -Force
    Bien "Modele copie depuis la cle"
} else {
    Info "Telechargement du modele '$Modele' (long au premier appel)..."
}

& $py -c "from faster_whisper import WhisperModel; WhisperModel(r'$ModeleIni', device='cpu', compute_type='int8'); print('Modele charge sans erreur.')"
if ($LASTEXITCODE -ne 0) {
    if ($ModeleIni -eq $Modele) {
        Arreter "Le telechargement du modele a echoue. Verifie la connexion Internet."
    } else {
        Arreter "Le modele copie depuis la cle est inutilisable.`n`n$ModeleIni`n`nLa copie sur la cle est peut-etre incomplete."
    }
}
Bien "Modele '$Modele' pret"

if ($posercpp) {
    $cible = Join-Path $Destination "whisper-cpp"
    New-Item -ItemType Directory -Force -Path $cible | Out-Null

    if ($copiercpp) {
        Copy-Item "$cppSurLaCle\*" $cible -Recurse -Force
        Bien "whisper.cpp copie depuis la cle"
    } else {
        $ProgressPreference = "SilentlyContinue"
        $zip = Join-Path $env:TEMP "whisper-bin-x64.zip"
        Info "Telechargement des binaires whisper.cpp ($WhisperCppTag)..."
        Invoke-WebRequest $WhisperCppUrl -OutFile $zip
        Expand-Archive -Path $zip -DestinationPath $cible -Force
        Remove-Item $zip -Force

        New-Item -ItemType Directory -Force -Path (Join-Path $cible "models") | Out-Null
        $binModele = Join-Path $cible "models\$WhisperCppModele"
        Info "Telechargement du modele ggml (547 Mo)..."
        if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
            curl.exe -L --fail --retry 3 -o $binModele $WhisperCppModeleUrl
        } else {
            Invoke-WebRequest $WhisperCppModeleUrl -OutFile $binModele
        }
        Bien "whisper.cpp installe"
    }

    # L'application retrouve seule ces chemins au premier lancement :
    # elle cherche un dossier whisper-cpp a cote d'elle.
    $exe = Get-ChildItem $cible -Filter "whisper-cli.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($exe) { Info "whisper-cli.exe : $($exe.FullName)" }
    else { Souci "whisper-cli.exe introuvable dans le dossier installe." }
}


# -------------------------------------------------------------
#  8. Lanceur, reglages, raccourci
# -------------------------------------------------------------
Etape 8 "Lanceur et raccourci..."

# pythonw.exe : meme interpreteur, sans fenetre console noire derriere
# l'interface.
$bat = @"
@echo off
rem Lanceur de l'application de transcription.
cd /d "%~dp0"
start "" ".venv\Scripts\pythonw.exe" "transcription_gui.py"
"@
$cheminBat = Join-Path $Destination "Lancer.bat"
Set-Content -Path $cheminBat -Value $bat -Encoding ASCII
Bien "Lancer.bat"

# Premier lancement a blanc : le .ini se cree avec les bons chemins et
# les chemins de whisper.cpp se remplissent tout seuls. Cela evite que
# la premiere ouverture serve a ca.
& $py -c "import sys; sys.path.insert(0, r'$Destination'); import transcription_gui as g; c = g.charger_config(); c['transcription']['threads'] = '$threads'; c['transcription']['modele'] = r'$ModeleIni'; c['whisper_cpp']['threads'] = '$threads'; g.sauver_config(c)"
if (Test-Path $ini) { Bien "transcription.ini genere ($threads threads)" }

if (-not $SansRaccourci) {
    try {
        $bureau = [Environment]::GetFolderPath("Desktop")
        $lnk = Join-Path $bureau "Transcription de seance.lnk"
        $sh = New-Object -ComObject WScript.Shell
        $r = $sh.CreateShortcut($lnk)
        $r.TargetPath = Join-Path $venv "Scripts\pythonw.exe"
        $r.Arguments = '"' + (Join-Path $Destination "transcription_gui.py") + '"'
        $r.WorkingDirectory = $Destination
        $r.Description = "Enregistrement et transcription de seance"
        $r.Save()
        Bien "Raccourci sur le Bureau"
    } catch {
        Souci "Raccourci non cree : $_"
    }
}


# -------------------------------------------------------------
#  Fin
# -------------------------------------------------------------
Titre "Installation terminee"
Write-Host ""
Write-Host "  Dossier   : $Destination"
Write-Host "  Moteurs   : faster-whisper ($Modele)$(if ($posercpp) {' + whisper.cpp'})"
Write-Host "  Lancement : raccourci du Bureau, ou $cheminBat"
Write-Host ""

if (Demander "Installation terminee.`n`n$Destination`n`nLancer l'application maintenant ?" "Termine") {
    Start-Process -FilePath (Join-Path $venv "Scripts\pythonw.exe") `
                  -ArgumentList ('"' + (Join-Path $Destination "transcription_gui.py") + '"') `
                  -WorkingDirectory $Destination
}
