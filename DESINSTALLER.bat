@echo off
rem ============================================================
rem  Double-clic sur ce fichier pour desinstaller l'application.
rem
rem  Les enregistrements et les transcriptions ne sont jamais
rem  supprimes sans une reponse explicite, et une sauvegarde est
rem  proposee avant.
rem
rem  Le script est cherche dans scripts\ (disposition de la cle),
rem  puis a cote de ce fichier : c'est ainsi que l'installeur le
rem  depose dans l'installation, a plat.
rem ============================================================
title Desinstallation - Transcription de seance

set "SCRIPT=%~dp0scripts\Desinstaller-Transcription.ps1"
if not exist "%SCRIPT%" set "SCRIPT=%~dp0Desinstaller-Transcription.ps1"

if not exist "%SCRIPT%" (
    echo.
    echo   ERREUR : Desinstaller-Transcription.ps1 est introuvable.
    echo   Il doit se trouver dans scripts\ ou a cote de ce fichier.
    echo.
    pause
    exit /b 1
)

rem  Surtout PAS de "cd /d %~dp0" : lance depuis l'installation, ce
rem  dossier deviendrait le dossier courant du processus, et Windows
rem  refuse de supprimer un dossier utilise comme tel.
cd /d "%SystemRoot%"

rem  Ce fichier est-il DANS l'installation qui va disparaitre ?
if exist "%~dp0.venv" goto :depuis_installation
if exist "%~dp0Lancer.bat" goto :depuis_installation

rem  --- Depuis la cle : le .bat survit, on peut attendre et afficher ---
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
echo.
echo ------------------------------------------------------------
echo  Tu peux fermer cette fenetre.
echo ------------------------------------------------------------
pause
exit /b 0

:depuis_installation
rem  Ce fichier va etre supprime pendant son execution. Sans "start",
rem  cmd chercherait la ligne suivante dans un fichier disparu et
rem  afficherait "Le fichier de commandes est introuvable". On lance
rem  donc la desinstallation dans sa propre fenetre et on rend la main
rem  tout de suite. Le compte rendu final s'affiche dans une boite de
rem  dialogue, succes comme echec.
start "Desinstallation - Transcription de seance" powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
exit /b 0
