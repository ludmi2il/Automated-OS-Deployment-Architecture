# Procedimiento para Creación de Golden Image (Pre-Sysprep)

Este documento detalla el paso a paso para preparar y generalizar una imagen maestra de Windows (Golden Image) dentro del entorno virtualizado (Hyper-V) antes de su captura con FOG Project.

## 1. Bypass de validación para Windows 11 (Opcional)
*Solo necesario si la imagen es de Windows 11 y el entorno virtual no cuenta con TPM 2.0 ni Secure Boot (requerido para el despliegue posterior vía PXE).*

1. Desactivar **TPM 2.0** y **Secure Boot** en la configuración de la máquina virtual.
2. Al bootear la ISO de instalación, presionar `SHIFT + F10` para abrir CMD y ejecutar `regedit`.
3. Navegar hasta `HKEY_LOCAL_MACHINE\SYSTEM\Setup` y crear una nueva clave llamada `LabConfig`.
4. Dentro de la clave, crear los siguientes valores **DWORD (32 bits)** en 1:
   - `BypassTPMCheck`
   - `BypassSecureBootCheck`
   - `BypassRAMCheck`
   - `BypassCPUCheck`
   - `BypassStorageCheck`

## 2. Ingreso en Modo Auditoría (Audit Mode)
Para ingresar con el usuario Administrador nativo **sin crear una cuenta de usuario local**, presionar `CTRL + SHIFT + F3` en la pantalla inicial de configuración (OOBE). 
- En este entorno, instalar todo el software base requerido para la Golden Image.

## 3. Desactivación de BitLocker
Asegurar que BitLocker esté completamente desactivado en la unidad principal para evitar fallas durante la generalización de Sysprep y la posterior clonación.

## 4. Instalación y configuración de FOG Client
1. Descargar el instalador de FOG Client desde el panel web del servidor FOG.
2. Realizar la instalación estándar.
3. Abrir CMD (como Administrador) y ejecutar los siguientes comandos para detener y deshabilitar el servicio. Este servicio será reactivado automáticamente al finalizar el despliegue mediante el script `SetupComplete.cmd`:
   ```cmd
   net stop FOGService
   sc config FOGService start= disabled
   ```

## 5. Automatización del Sellado (Sysprep & OOBE)
Los pasos manuales de copiado de archivos y ejecución de Sysprep han sido reemplazados por un proceso automatizado para eliminar el riesgo de error humano.

1. Descargar este repositorio (en formato ZIP) y descomprimirlo.
2. Eliminar el archivo `.zip` original de forma permanente (`Shift + Supr`).
3. Entrar a la carpeta `golden-image` y hacer doble clic en el archivo `seal-image-launcher.bat`. El script hará la limpieza final y la máquina virtual se apagará sola.

Este script orquesta el cierre de la imagen:
   - Inyecta el directorio de scripts de post-despliegue en `C:\Windows\Setup\Scripts`.
   - Copia el archivo de respuestas (`unattend.xml`) a `C:\Windows\System32\Sysprep\Panther`.
   - Ejecuta `sysprep.exe` con los parámetros `/generalize /oobe /shutdown` apuntando al XML de forma desatendida.
   - Elimina automáticamente la carpeta del repositorio para no dejar rastros en el sistema.

> ⚠️ **Nota:** Una vez finalizado el script, la máquina virtual se apagará sola. A partir de este momento, el disco está sellado y listo para ser capturado por FOG. No volver a iniciar la VM a menos que sea directamente por red (PXE) para la captura.