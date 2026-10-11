<#
.SYNOPSIS
    Redirección de carpetas de usuario (User Shell Folders)
.DESCRIPTION
    Modifica el NTUSER.DAT del Default User para redirigir los perfiles a D:\Usuarios.
    Utiliza reg.exe nativo con expansión diferida (REG_EXPAND_SZ) para evitar bloqueos de Hive.
.NOTES
    Author: Ludmila Dosil (@ludmi2il)
#>

$LogFile = "C:\Windows\Logs\Redirect_Folders.log"

# ==============================================================================
# 1. DEFINICIÓN DE FUNCIONES Y DATOS
# ==============================================================================

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logLine = "[$timestamp] $Message"
    
    # Escribe en el archivo de log y también en la salida estándar
    Add-Content -Path $LogFile -Value $logLine -Encoding UTF8 -ErrorAction SilentlyContinue
    Write-Output $logLine
}

function Test-DataDriveAvailable {
    param([string]$DriveLetter = 'D')
    
    $vol = Get-Volume -DriveLetter $DriveLetter -ErrorAction SilentlyContinue | 
           Where-Object { $_.FileSystemLabel -eq 'Datos' -or $_.DriveLetter -eq $DriveLetter }
    return ($null -ne $vol)
}

function Initialize-ProfilesRoot {
    param([string]$BasePath = "D:\Usuarios")
    
    if (-not (Test-Path $BasePath)) {
        try {
            New-Item -Path $BasePath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        catch {
            throw "No se pudo crear el directorio raíz '$BasePath'. Detalle: $($_.Exception.Message)"
        }
    }
}

function Get-ShellFolderMappings {
    return [ordered]@{
        # A. Carpetas Principales
        "Desktop"                                = "Desktop"
        "Personal"                               = "Documents"
        "{374DE290-123F-4565-9164-39C4925E467B}" = "Downloads"

        # B. Multimedia
        "My Pictures"                            = "Pictures"
        "My Video"                               = "Videos"
        "My Music"                               = "Music"

        # C. Opcionales
        "Favorites"                              = "Favorites"
        "{56784854-C6CB-462B-8169-88E350ACB882}" = "Contacts"
        "{7D1D3A04-DEBB-4115-95CF-2F29DA2920DA}" = "Searches"
        "{BFB9D5E0-C6A9-404C-B2B2-AE6DB6AF4968}" = "Links"
        "{31C0DD25-9439-4F12-BF41-7FF4EDA38722}" = "3D Objects"
    }
}

function Set-DefaultUserShellFolders {
    param(
        [System.Collections.Specialized.OrderedDictionary]$FolderMappings,
        [string]$BasePath = "D:\Usuarios"
    )

    $hiveName = "HKU\DefaultUser"
    $ntUserPath = "C:\Users\Default\NTUSER.DAT"
    $regPath = "$hiveName\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"

    if (-not (Test-Path $ntUserPath)) {
        throw "No se encontró el archivo base en '$ntUserPath'."
    }

    # Cargar el hive del Default User
    & reg.exe load $hiveName $ntUserPath | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Fallo al montar el archivo NTUSER.DAT con reg.exe (ExitCode: $LASTEXITCODE)."
    }

    try {
        foreach ($entry in $FolderMappings.GetEnumerator()) {
            $targetPath = "$BasePath\%USERNAME%\$($entry.Value)"
            & reg.exe add $regPath /v $entry.Key /t REG_EXPAND_SZ /d $targetPath /f | Out-Null
            
            if ($LASTEXITCODE -ne 0) {
                throw "Fallo al inyectar la clave '$($entry.Key)' hacia '$targetPath' (ExitCode: $LASTEXITCODE)."
            }
        }
    }
    finally {
        # El bloque finally se ejecuta SIEMPRE antes de que el throw suba al catch principal,
        # garantizando que el NTUSER.DAT nunca quede bloqueado en memoria.
        [gc]::Collect()
        [gc]::WaitForPendingFinalizers()
        & reg.exe unload $hiveName | Out-Null
    }
}

# ==============================================================================
# 2. LÓGICA PRINCIPAL (WORKFLOW)
# ==============================================================================

try {
    Write-Log "[START] Iniciando script de redirección de carpetas de usuario."

    if (Test-DataDriveAvailable -DriveLetter 'D') {
        Write-Log "[INFO] Unidad D: detectada. Iniciando redirección de perfiles..."

        Initialize-ProfilesRoot -BasePath "D:\Usuarios"
        Write-Log "[INFO] Directorio raíz D:\Usuarios verificado."
        
        $mappings = Get-ShellFolderMappings
        Set-DefaultUserShellFolders -FolderMappings $mappings -BasePath "D:\Usuarios"

        Write-Log "[OK] Redirección inyectada con éxito en el Default User."
    } else {
        Write-Log "[SKIP] Unidad D: no detectada. Se omite la redirección de perfiles (permanecen en C:\)."
    }
}
catch {
    Write-Log "[ERROR CRÍTICO] La redirección de perfiles falló: $($_.Exception.Message)"
    exit 1
}