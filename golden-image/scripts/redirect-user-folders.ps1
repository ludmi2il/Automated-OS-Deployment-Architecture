# Cargar el registro del perfil por defecto (Default User)
reg load "HKU\DefaultUser" "C:\Users\Default\NTUSER.DAT"

$regPath = "HKU\DefaultUser\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"

# Función rápida para inyectar forzando el tipo ExpandString
function Set-ShellFolder ($name, $folder) {
    New-ItemProperty -Path $regPath -Name $name -Value "D:\Usuarios\%USERNAME%\$folder" -PropertyType ExpandString -Force | Out-Null
}

# 1. Carpetas de Trabajo Principales
Set-ShellFolder "Desktop" "Desktop"
Set-ShellFolder "Personal" "Documents"
Set-ShellFolder "{374DE290-123F-4565-9164-39C4925E467B}" "Downloads"

# 2. Multimedia
Set-ShellFolder "My Pictures" "Pictures"
Set-ShellFolder "My Video" "Videos"
Set-ShellFolder "My Music" "Music"

# 3. Opcionales (Favoritos, Contactos, Búsquedas guardadas)
Set-ShellFolder "Favorites" "Favorites"
Set-ShellFolder "{56784854-C6CB-462B-8169-88E350ACB882}" "Contacts"
Set-ShellFolder "{7D1D3A04-DEBB-4115-95CF-2F29DA2920DA}" "Searches"
Set-ShellFolder "{BFB9D5E0-C6A9-404C-B2B2-AE6DB6AF4968}" "Links"
Set-ShellFolder "{31C0DD25-9439-4F12-BF41-7FF4EDA38722}" "3D Objects"

# Descargar el registro para guardar los cambios en el archivo
reg unload "HKU\DefaultUser"