<#
.SYNOPSIS
    Automated Zero-Touch Sealing Image Script
.DESCRIPTION
    Automatiza el sellado desatendido de la imagen base. Copia los scripts de post-despliegue a Setup\Scripts, inyecta el archivo de respuestas unattend.xml en Panther y ejecuta Sysprep para generalizar y apagar el equipo.
.NOTES
    Author: Ludmila Dosil (@ludmi2il)
    Requirement: Sesión de PowerShell con privilegios elevados (Run as Administrator).
#>

# ==============================================================================
# 1. DEFINICIÓN DE FUNCIONES
# ==============================================================================

function Test-Administrator {
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Este script debe ejecutarse como Administrador (Run as Administrator)."
    }
}

function Get-RepositoryRoot {
    param (
        [string]$ScriptDir
    )
    
    $InnerRepo = Split-Path -Path $ScriptDir -Parent 
    $OuterRepo = Split-Path -Path $InnerRepo -Parent

    # Rutina Anti-Mamushka
    $InnerName = Split-Path -Path $InnerRepo -Leaf
    $OuterName = Split-Path -Path $OuterRepo -Leaf

    if ($InnerName -eq $OuterName) {
        Write-Host "Estructura duplicada detectada al extraer. Se apuntará a la carpeta raíz exterior." -ForegroundColor Yellow
        return $OuterRepo
    } else {
        return $InnerRepo
    }
}

function Copy-Payloads {
    param (
        [string]$ScriptDir
    )
    $DestScripts = "C:\Windows\Setup\Scripts"
    $DestPanther = "C:\Windows\System32\Sysprep\Panther"
    
    $SourceScripts = Join-Path -Path $ScriptDir -ChildPath "scripts"
    $SourceXML = Join-Path -Path $ScriptDir -ChildPath "sysprep\unattend.xml"

    # Creación de directorios
    if (-not (Test-Path $DestScripts)) { New-Item -ItemType Directory -Path $DestScripts -Force | Out-Null }
    if (-not (Test-Path $DestPanther)) { New-Item -ItemType Directory -Path $DestPanther -Force | Out-Null }

    # Inyección de archivos
    Copy-Item -Path "$SourceScripts\*" -Destination $DestScripts -Recurse -Force
    Copy-Item -Path $SourceXML -Destination $DestPanther -Force
}

function Invoke-GhostSysprep {
    param (
        [string]$RepoRoot
    )
    
    $GhostCommand = "Start-Sleep -Seconds 3; Remove-Item -LiteralPath '$RepoRoot' -Recurse -Force; C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown /unattend:C:\Windows\System32\Sysprep\Panther\unattend.xml"

    # Obligamos al proceso oculto a nacer en C:\ para que no bloquee la carpeta
    Start-Process -FilePath "powershell.exe" -ArgumentList "-WindowStyle Hidden -Command `"$GhostCommand`"" -WorkingDirectory "C:\"
}

# ==============================================================================
# 2. LÓGICA PRINCIPAL (WORKFLOW)
# ==============================================================================

try {
    Test-Administrator
    Write-Host "Iniciando sellado de Golden Image..." -ForegroundColor Cyan

    $ScriptDir = $PSScriptRoot
    $RepoRoot = Get-RepositoryRoot -ScriptDir $ScriptDir

    Write-Host "Inyectando cargas útiles en el sistema..."
    Copy-Payloads -ScriptDir $ScriptDir

    Write-Host "Ejecutando orquestador final y limpiando rastros. La VM se apagará sola." -ForegroundColor Green
    Invoke-GhostSysprep -RepoRoot $RepoRoot
    exit
} catch {
    Write-Error "Ocurrió un error inesperado: $($_.Exception.Message)"
    Pause
}