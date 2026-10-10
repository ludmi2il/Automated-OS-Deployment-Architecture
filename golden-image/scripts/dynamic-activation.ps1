<#
.SYNOPSIS
    KMS Dynamic Auto-Activation Script (Modular)
.DESCRIPTION
    Detecta la edición de Windows y verifica claves OEM embebidas en BIOS/UEFI. 
    De lo contrario, instala la GVLK correspondiente y activa vía KMS.
    El servidor KMS se inyecta dinámicamente mediante un archivo 'kms.env' 
    o recurre al auto-descubrimiento por DNS (SRV) como fallback.
    Arquitectura modular con captura de errores para entornos Zero-Touch.
.NOTES
    Author: Ludmila Dosil (@ludmi2il)
#>

$LogFile = "C:\Windows\Logs\KMS_Activation.log"
$EnvFile = Join-Path -Path $PSScriptRoot -ChildPath "kms.env"
$Slmgr   = "$env:windir\System32\slmgr.vbs"

if (-not (Test-Path -Path (Split-Path $LogFile -Parent))) { New-Item -ItemType Directory -Path (Split-Path $LogFile -Parent) -Force | Out-Null }

# ==============================================================================
# 1. DEFINICIÓN DE FUNCIONES
# ==============================================================================

function Write-Log ([string]$Message) {
    $LogLine = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    Out-File -FilePath $LogFile -InputObject $LogLine -Append -Encoding UTF8
}

function Test-WindowsAlreadyActivated {
    Write-Log "Verificando estado de activación actual..."
    try {
        # LicenseStatus = 1 significa 'Licensed'
        $license = Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL" |
                   Where-Object { $_.Name -like "*Windows*" -and $_.LicenseStatus -eq 1 }
        
        if ($license) {
            Write-Log "El sistema ya se encuentra activado legítimamente ($($license.Description))."
            return $true
        }
    } catch {
        Write-Log "Advertencia: No se pudo consultar SoftwareLicensingProduct vía CIM: $($_.Exception.Message)"
    }
    return $false
}

function Get-BiosEmbeddedKey {
    Write-Log "Buscando clave OEM en la tabla ACPI/MSDM de la BIOS..."
    try {
        $oa3x = Get-CimInstance -Namespace "root\cimv2" -ClassName SoftwareLicensingService -ErrorAction Stop
        if ($oa3x.OA3xOriginalProductKey) {
            Write-Log "Clave OEM detectada en la BIOS."
            return $oa3x.OA3xOriginalProductKey
        }
    } catch {
        Write-Log "No se encontró tabla MSDM o falló la consulta CIM."
    }
    return $null
}

function Get-WindowsEditionKey {
    Write-Log "Detectando edición del sistema operativo..."
    $ProductName = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name "ProductName" -ErrorAction Stop).ProductName
    
    if (-not $ProductName) { throw "No se pudo recuperar el ProductName del Registro." }

    if ($ProductName -match "LTSC" -or $ProductName -match "LTSB") {
        Write-Log "Edición detectada: $ProductName. Asignando GVLK LTSC."
        return "M7XTQ-FN8P6-TTKYV-9D4CC-J462D"
    } else {
        Write-Log "Edición detectada: $ProductName. Asignando GVLK Pro/Enterprise."
        return "W269N-WFGWX-YVC9B-4J6C9-T83GX"
    }
}

function Install-ProductKey ([string]$Key) {
    Write-Log "Inyectando clave de producto..."
    $Output = & cscript.exe //B //Nologo $Slmgr /ipk $Key 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Fallo la inyección de la clave (/ipk). Salida: $Output" }
    Write-Log "Clave inyectada con éxito."
}

function Get-KmsServerFromEnv {
    if (-not (Test-Path -Path $EnvFile)) { return $null }
    
    Write-Log "Archivo .env detectado. Analizando..."
    $EnvContent = Get-Content -Path $EnvFile -ErrorAction Stop
    
    foreach ($Line in $EnvContent) {
        if ($Line -match "^KMS_SERVER=(.+)$") { return $Matches[1].Trim() }
    }
    
    # Fallback si solo inyectaron la IP
    if ($EnvContent.Length -gt 0 -and $EnvContent[0] -notmatch "=") { return $EnvContent[0].Trim() }
    return $null
}

function Set-KmsServer ([string]$Server) {
    Write-Log "Apuntando al servidor KMS dinámico: $Server"
    $Output = & cscript.exe //B //Nologo $Slmgr /skms $Server 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Fallo la asignación del servidor KMS (/skms). Salida: $Output" }
}

function Invoke-KmsActivation {
    Write-Log "Solicitando activación al servidor..."
    $Output = & cscript.exe //B //Nologo $Slmgr /ato 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Fallo la activación (/ato). Salida: $Output" }
    Write-Log "Windows activado correctamente."
}

# ==============================================================================
# 2. ORQUESTADOR PRINCIPAL (WORKFLOW)
# ==============================================================================

function Invoke-AutoActivationWorkflow {
    try {
        Write-Log "==================================================="
        Write-Log "INICIO DE ACTIVACIÓN MODULAR"

        if (Test-WindowsAlreadyActivated) {
            Write-Log "Omitiendo proceso KMS: el equipo ya cuenta con licencia activa."
            Write-Log "PROCESO FINALIZADO"
            Write-Log "==================================================="
            return
        }

        $BiosKey = Get-BiosEmbeddedKey
        $OemActivated = $false

        if ($BiosKey) {
            try {
                Write-Log "Intentando activar utilizando la clave OEM de la BIOS..."
                Install-ProductKey -Key $BiosKey
                & cscript.exe //B //Nologo $Slmgr /ckms | Out-Null
                Invoke-KmsActivation
                $OemActivated = $true
                Write-Log "Activación OEM completada exitosamente."
            } catch {
                Write-Log "Aviso: Clave OEM no válida para esta edición (ej. Home vs Pro) o sin red. Detalle: $($_.Exception.Message)"
                Write-Log "Continuando hacia el flujo de activación KMS..."
            }
        }

        if (-not $OemActivated) {
            $Key = Get-WindowsEditionKey
            Install-ProductKey -Key $Key

            $KmsServer = Get-KmsServerFromEnv
            if ($KmsServer) {
                Set-KmsServer -Server $KmsServer
            } else {
                Write-Log "Sin .env definido. Confiando en Auto-descubrimiento DNS (SRV)."
            }

            Invoke-KmsActivation
        }

        Write-Log "PROCESO FINALIZADO SIN ERRORES"
        Write-Log "==================================================="
    } catch {
        Write-Log "ERROR CRÍTICO GENERAL: $($_.Exception.Message)"
        Write-Log "PROCESO ABORTADO"
        Write-Log "==================================================="
        # Retornamos un código de error al sistema operativo por si SetupComplete.cmd necesita saber que falló
        exit 1 
    }
}

# ==============================================================================
# 3. EJECUCIÓN
# ==============================================================================
Invoke-AutoActivationWorkflow