<#
.SYNOPSIS
    Redirección de carpetas de usuario (User Shell Folders)
.DESCRIPTION
    Modifica el NTUSER.DAT del Default User para redirigir los perfiles a D:\Usuarios.
    Solo se ejecuta si la partición D: fue creada previamente.
#>

# Comprobar de forma silenciosa si el volumen D: existe en el sistema
$dataDriveExists = Get-Volume -DriveLetter D -ErrorAction SilentlyContinue | Where-Object { $_.FileSystemLabel -eq 'Datos' }

# Si el disco D: existe, procedemos con la inyección en el registro
if ($null -ne $dataDriveExists) {
    
    # Cargar el registro del perfil por defecto (Default User) de forma silenciosa
    reg load "HKU\DefaultUser" "C:\Users\Default\NTUSER.DAT" | Out-Null

    $regPath = "HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"

    # Función rápida para inyectar forzando el tipo ExpandString
    function Set-ShellFolder {
        param(
            [string]$Name, 
            [string]$Folder
        )
        New-ItemProperty -Path $regPath -Name $Name -Value "D:\Usuarios\%USERNAME%\$Folder" -PropertyType ExpandString -Force | Out-Null
    }

    # 1. Carpetas de Trabajo Principales
    Set-ShellFolder -Name "Desktop" -Folder "Desktop"
    Set-ShellFolder -Name "Personal" -Folder "Documents"
    Set-ShellFolder -Name "{374DE290-123F-4565-9164-39C4925E467B}" -Folder "Downloads"

    # 2. Multimedia
    Set-ShellFolder -Name "My Pictures" -Folder "Pictures"
    Set-ShellFolder -Name "My Video" -Folder "Videos"
    Set-ShellFolder -Name "My Music" -Folder "Music"

    # 3. Opcionales (Favoritos, Contactos, Búsquedas guardadas)
    Set-ShellFolder -Name "Favorites" -Folder "Favorites"
    Set-ShellFolder -Name "{56784854-C6CB-462B-8169-88E350ACB882}" -Folder "Contacts"
    Set-ShellFolder -Name "{7D1D3A04-DEBB-4115-95CF-2F29DA2920DA}" -Folder "Searches"
    Set-ShellFolder -Name "{BFB9D5E0-C6A9-404C-B2B2-AE6DB6AF4968}" -Folder "Links"
    Set-ShellFolder -Name "{31C0DD25-9439-4F12-BF41-7FF4EDA38722}" -Folder "3D Objects"

    # Descargar el registro para guardar los cambios
    reg unload "HKU\DefaultUser" | Out-Null

} else {
    # Fallback silencioso: no se hace nada
    Write-Output "Unidad D: no detectada. Se omite la redirección de perfiles (permanecen en C:\)."
}