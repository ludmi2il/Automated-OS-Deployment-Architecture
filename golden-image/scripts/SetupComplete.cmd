@echo off
:: SetupComplete.cmd principal

:: Configuración dinámica de particiones de Sistema y Datos
powershell.exe -ExecutionPolicy Bypass -File "C:\Windows\Setup\Scripts\disc-config.ps1"

:: Redirección de la carepta de usuario default a la partición de Datos
powershell.exe -ExecutionPolicy Bypass -File "C:\Windows\Setup\Scripts\redirect-user-folders.ps1"

:: Activa el Windows por KMS
:: call "C:\Windows\Setup\Scripts\Activar Windows 11 Pro.bat"

:: Despierta al cliente FOG por si queda algo para instalar
sc config FOGService start= auto
net start FOGService

:: Borrar toda la carpeta de scripts para no dejar rastro al usuario final
cd \
rd /s /q "%WINDIR%\Setup\Scripts"