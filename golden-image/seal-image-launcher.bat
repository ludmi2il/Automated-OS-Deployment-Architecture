@echo off
:: Soltamos el directorio actual yendo a la raiz del disco
cd \

:: Ejecutamos el orquestador (la variable %~dp0 funciona perfecto aunque hayamos hecho 'cd \')
powershell.exe -ExecutionPolicy Bypass -File "%~dp0seal-image.ps1"