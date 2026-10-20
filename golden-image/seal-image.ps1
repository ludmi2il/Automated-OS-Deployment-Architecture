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

function Test-SysprepStatus {
    if (Get-Process -Name "sysprep" -ErrorAction SilentlyContinue) {
        throw "Error: Sysprep ya se encuentra en ejecución. Cerralo antes de lanzar el script."
    }
}

function Test-BitLockerStatus {
    $bdeStatus = manage-bde -status C: | Out-String
    if ($bdeStatus -match "Protection On" -or $bdeStatus -match "Protección activada") {
        throw "Error: BitLocker se encuentra ACTIVADO en C:. Desencriptá la unidad antes de sellar la imagen."
    }
}

function Test-PreflightChecks {
    Write-Host "Realizando comprobaciones de entorno..." -ForegroundColor Cyan
    
    Test-Administrator
    Test-SysprepStatus
    Test-BitLockerStatus
    
    Write-Host "Todas las comprobaciones pasaron con éxito. El entorno está listo." -ForegroundColor Green
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

function Install-OfficePreSysprep {
    param (
        [string]$XmlPath
    )

    # Cláusula de guarda: Validamos que el XML exista antes de hacer nada
    if (-not (Test-Path $XmlPath)) {
        throw "El archivo de configuración de Office no existe en la ruta: $XmlPath"
    }

    $TempFolder   = "C:\Temp\ODT"
    $DetailsPage  = "https://www.microsoft.com/en-us/download/details.aspx?id=49117"
    $UserAgent    = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    $InstallerExe = "$TempFolder\odt.exe"
    $SetupExe     = "$TempFolder\setup.exe"

    Write-Host "Obteniendo la URL dinámica más reciente de ODT..." -ForegroundColor Cyan
    
    # -ErrorAction Stop fuerza a que si falla la petición web, salte directo al catch principal
    $Page = Invoke-WebRequest -Uri $DetailsPage -UserAgent $UserAgent -UseBasicParsing -ErrorAction Stop

    # 1. Extracción por estructura de links
    $OdtUrl = ($Page.Links | Where-Object { $_.href -match "download\.microsoft\.com.*officedeploymenttool.*\.exe$" }).href | Select-Object -First 1

    # 2. Fallback mediante Regex
    if (-not $OdtUrl -and $Page.Content -match '(https://download\.microsoft\.com/download/[^"'']+/officedeploymenttool[^"'']*\.exe)') {
        $OdtUrl =$Matches[1]
    }

    # Cláusula de guarda: Si no hay URL, tiramos throw directo
    if (-not $OdtUrl) { 
        throw "No se pudo extraer la URL dinámica ejecutable de ODT desde el HTML de Microsoft." 
    }

    Write-Host "URL resuelta exitosamente: $OdtUrl" -ForegroundColor Green

    if (-not (Test-Path $TempFolder)) { New-Item -ItemType Directory -Path $TempFolder -Force | Out-Null }

    Write-Host "Descargando Office Deployment Tool..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $OdtUrl -OutFile $InstallerExe -UseBasicParsing -ErrorAction Stop

    Write-Host "Extrayendo setup.exe..." -ForegroundColor Cyan
    Start-Process -FilePath $InstallerExe -ArgumentList "/quiet /extract:`"$TempFolder`"" -Wait

    # Verificamos que la extracción haya generado el setup.exe
    if (-not (Test-Path $SetupExe)) {
        throw "Error al extraer ODT: No se encontró setup.exe en $TempFolder"
    }

    Write-Host "Instalando Office..." -ForegroundColor Cyan
    Start-Process -FilePath $SetupExe -ArgumentList "/configure `"$XmlPath`"" -Wait

    Write-Host "Limpiando archivos temporales..." -ForegroundColor Green
    Remove-Item -Path $TempFolder -Recurse -Force -ErrorAction SilentlyContinue
}

function Install-ChocolateyPreSysprep {
    Write-Host "Instalando Chocolatey Package Manager..." -ForegroundColor Cyan

    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

    # 1. Intentamos descargar el script a una variable
    $ChocoScript = (New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')

    # Cláusula de guarda: Si la descarga devuelve algo vacío, abortamos
    if ([string]::IsNullOrWhiteSpace($ChocoScript)) {
        throw "No se pudo obtener el script de instalación de Chocolatey (descarga vacía o sin red)."
    }

    # Ejecutamos el script descargado
    Invoke-Expression $ChocoScript

    # 2. Cláusula de guarda post-instalación: Confirmamos que el binario exista en el disco
    $ChocoExe = "$env:ProgramData\chocolatey\bin\choco.exe"
    if (-not (Test-Path $ChocoExe)) {
        throw "Error crítico: La instalación finalizó pero no se encontró el ejecutable en: $ChocoExe"
    }

    Write-Host "Refrescando variables de entorno..." -ForegroundColor Cyan
    Import-Module "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1" -ErrorAction SilentlyContinue
    
    if (Get-Command refreshenv -ErrorAction SilentlyContinue) {
        refreshenv
    }

    Write-Host "Chocolatey instalado y verificado correctamente." -ForegroundColor Green
}

function Invoke-GhostSysprep {
    param (
        [string]$RepoRoot
    )
    
    $GhostCommand = "Start-Sleep -Seconds 3; Remove-Item -LiteralPath '$RepoRoot.zip' -Recurse -Force; Remove-Item -LiteralPath '$RepoRoot' -Recurse -Force; C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown /unattend:C:\Windows\System32\Sysprep\Panther\unattend.xml"

    # Obligamos al proceso oculto a nacer en C:\ para que no bloquee la carpeta
    Start-Process -FilePath "powershell.exe" -ArgumentList "-WindowStyle Hidden -Command `"$GhostCommand`"" -WorkingDirectory "C:\"
}

# ==============================================================================
# 2. LÓGICA PRINCIPAL (WORKFLOW)
# ==============================================================================

try {
    Test-PreflightChecks
    Write-Host "Iniciando sellado de Golden Image..." -ForegroundColor Cyan

    $ScriptDir = $PSScriptRoot
    $RepoRoot = Get-RepositoryRoot -ScriptDir $ScriptDir

    Write-Host "Inyectando cargas útiles en el sistema..."
    Copy-Payloads -ScriptDir $ScriptDir

    $OfficeXmlPath = Join-Path -Path $RepoRoot -ChildPath "office\config.xml"
    Install-OfficePreSysprep -XmlPath $OfficeXmlPath
    
    Install-ChocolateyPreSysprep

    Write-Host "Ejecutando orquestador final y limpiando rastros. La VM se apagará sola." -ForegroundColor Green
    Invoke-GhostSysprep -RepoRoot $RepoRoot
    exit
} catch {
    Write-Error "Ocurrió un error inesperado: $($_.Exception.Message)"
    Pause
}