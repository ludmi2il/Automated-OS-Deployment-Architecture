# Procedimiento para Creación de Golden Image (Pre-Sysprep)

Este documento detalla el paso a paso para preparar y generalizar una imagen maestra de Windows (Golden Image) antes de su captura.

## 1. Bypass de validación para Windows 11 (Opcional)
*Solo necesario si la imagen es de Windows 11 y se está en un entorno virtual sin TPM 2.0 ni Secure Boot como en este caso que se va a utilizar despliegue por PXE desde FOG Server.*

1. Desactivar el **TPM 2.0** y **Secure Boot** en la configuración de la VM.
2. Al bootear la ISO de instalación, presionar `SHIFT + F10` para abrir CMD y ejecutar `regedit`.
3. Navegar hasta `HKEY_LOCAL_MACHINE\SYSTEM\Setup` y crear una nueva clave llamada `LabConfig`.
4. Dentro, crear dos valores **DWORD (32 bits)** en `1`:
   - `BypassTPMCheck`
   - `BypassSecureBootCheck`

## 2. Ingreso en Modo Auditoría (Audit Mode)
Para entrar con el usuario Administrador una vez instalado Windows, pero **SIN HABER CREADO EL USUARIO**, presionar `CTRL + SHIFT + F3` en la pantalla inicial (OOBE). 
- En este entorno, instalar todo el software que sea necesario para la imagen.

## 3. Desactivación de BitLocker
Desactivar BitLocker para asegurar que Sysprep pueda preparar la imagen correctamente.

## 4. Instalación y configuración de FOG Client
1. Descargar el instalador para Windows de FOG Client desde la web del servidor FOG.
2. Instalar FOG Client.
3. Vía CMD (como administrador), ejecutar estos dos comandos para detener y deshabilitar el servicio (será levantado recién cuando termine el `SetupComplete`):
   ```cmd
   net stop FOGService
   sc config FOGService start= disabled
   ```

## 5. Preparación de Scripts
Copiar el contenido de la carpeta [`scripts`](/scripts) del repositorio al directorio:
`C:\Windows\Setup\Scripts`

## 6. Archivo de Configuración Desatendida
Copiar el XML de configuración desatendida ([`unattend.xml`](/sysprep/unattend.xml)) al directorio:
`C:\Windows\System32\Sysprep`

## 7. Ejecución de Sysprep
Ejecutar el siguiente comando en CMD (con privilegios de Administrador) para generalizar y apagar la máquina:
```cmd
c:\windows\system32\sysprep\sysprep.exe /generalize /oobe /shutdown /unattend:c:\windows\system32\sysprep\unattend.xml
```