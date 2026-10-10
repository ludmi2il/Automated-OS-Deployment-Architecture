<#
.SYNOPSIS
    Redirección de carpetas de usuario (User Shell Folders)
.DESCRIPTION
    Modifica el NTUSER.DAT del Default User para redirigir los perfiles a D:\Usuarios.
    Utiliza RunOnce para la creación dinámica de carpetas y evita bloqueos de Hive.
#>

# Comprobar de forma silenciosa si el volumen D: existe en el sistema
$dataDriveExists = Get-Volume -DriveLetter D -ErrorAction SilentlyContinue | Where-Object { $_.FileSystemLabel -eq 'Datos' -or$_.DriveLetter -eq 'D' }

if ($null -ne$dataDriveExists) {
    Write-Output "[INFO] Unidad D: detectada. Iniciando redirección de perfiles..."

    # 1. Crear el directorio base si no existe (A nivel sistema)
    if (-not (Test-Path "D:\Usuarios")) {
        New-Item -Path "D:\Usuarios" -ItemType Directory -Force | Out-Null
    }

    # 2. Cargar el hive del Default User
    # Guardamos la salida para asegurar que se cargó bien antes de seguir
    $loadResult = & reg load "HKU\DefaultUser" "C:\Users\Default\NTUSER.DAT" 2>&1
    
    $regPath = "HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"

    # Función que usa reg.exe nativo (sin cmd.exe) para inyectar %USERNAME% de forma literal
    function Set-ShellFolder {
        param([string]$Name, [string]$Folder)
        $targetPath = "D:\Usuarios\%USERNAME%\$Folder"
        & reg.exe add $regPath /v $Name /t REG_EXPAND_SZ /d $targetPath /f | Out-Null
    }

    # ==========================================
    # A. Redirección de Carpetas Principales
    # ==========================================
    Set-ShellFolder -Name "Desktop" -Folder "Desktop"
    Set-ShellFolder -Name "Personal" -Folder "Documents"
    Set-ShellFolder -Name "{374DE290-123F-4565-9164-39C4925E467B}" -Folder "Downloads"

    # ==========================================
    # B. Multimedia
    # ==========================================
    Set-ShellFolder -Name "My Pictures" -Folder "Pictures"
    Set-ShellFolder -Name "My Video" -Folder "Videos"
    Set-ShellFolder -Name "My Music" -Folder "Music"

    # ==========================================
    # C. Opcionales
    # ==========================================
    Set-ShellFolder -Name "Favorites" -Folder "Favorites"
    Set-ShellFolder -Name "{56784854-C6CB-462B-8169-88E350ACB882}" -Folder "Contacts"
    Set-ShellFolder -Name "{7D1D3A04-DEBB-4115-95CF-2F29DA2920DA}" -Folder "Searches"
    Set-ShellFolder -Name "{BFB9D5E0-C6A9-404C-B2B2-AE6DB6AF4968}" -Folder "Links"
    Set-ShellFolder -Name "{31C0DD25-9439-4F12-BF41-7FF4EDA38722}" -Folder "3D Objects"

    # ==========================================
    # D. Limpieza y Desmontaje Seguro
    # ==========================================
    # Forzamos la recolección de basura de .NET por precaución extrema antes del unload
    [gc]::Collect()
    [gc]::WaitForPendingFinalizers()

    # Descargar el registro guardando los cambios
    & reg unload "HKU\DefaultUser" | Out-Null

    Write-Output "[OK] Redirección inyectada con éxito."

} else {
    Write-Output "[SKIP] Unidad D: no detectada. Se omite la redirección de perfiles (permanecen en C:\)."
}