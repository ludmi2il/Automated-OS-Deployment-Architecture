@echo off
:: SetupComplete.cmd principal

:: Configuración dinámica de particiones de Sistema y Datos
powershell.exe -ExecutionPolicy Bypass -File "C:\Windows\Setup\Scripts\disc-config.ps1"

:: Redirección de la carpeta de usuario default a la partición de Datos
powershell.exe -ExecutionPolicy Bypass -File "C:\Windows\Setup\Scripts\redirect-user-folders.ps1"

:: Activa el Windows 
powershell.exe -ExecutionPolicy Bypass -File "C:\Windows\Setup\Scripts\dynamic-activation.ps1"

:: Despierta al cliente FOG por si queda algo para instalar
sc config FOGService start= auto
net start FOGService

:: Borrar toda la carpeta de scripts para no dejar rastro al usuario final
cd \
rd /s /q "%WINDIR%\Setup\Scripts"