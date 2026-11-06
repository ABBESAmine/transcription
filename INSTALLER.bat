@echo off
rem ============================================================
rem  Double-clic sur ce fichier pour installer l'application.
rem
rem  Il ne fait qu'appeler le script d'installation : Windows refuse
rem  d'executer un .ps1 au double-clic, et -ExecutionPolicy Bypass
rem  evite d'avoir a modifier un reglage de la machine.
rem
rem  Le script est cherche dans scripts\ (disposition de la cle),
rem  puis a cote de ce fichier (dossier a plat).
rem ============================================================
title Installation - Transcription de seance
cd /d "%~dp0"

set "SCRIPT=%~dp0scripts\Installer-Transcription.ps1"
if not exist "%SCRIPT%" set "SCRIPT=%~dp0Installer-Transcription.ps1"

if not exist "%SCRIPT%" (
    echo.
    echo   ERREUR : Installer-Transcription.ps1 est introuvable.
    echo   Il doit se trouver dans scripts\ ou a cote de ce fichier.
    echo.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*

echo.
echo ------------------------------------------------------------
echo  Tu peux fermer cette fenetre.
echo ------------------------------------------------------------
pause
