<#
.SYNOPSIS
    Automated Zero-Touch Disk Configuration Script
.DESCRIPTION
    Prepara y particiona unidades de almacenamiento de forma dinámica en entornos Sysprep.
#>

# ==============================================================================
# 1. DEFINICIÓN DE FUNCIONES
# ==============================================================================

function Clear-DriveLetter {
    param(
        [string]$Letter = 'D' # Valor por defecto
    )

    if (Get-Volume -DriveLetter $Letter -ErrorAction SilentlyContinue) {
        @"
select volume $Letter
assign letter=Z
"@ | diskpart | Out-Null
        Start-Sleep -Seconds 2
    }
}

function Remove-RecoveryPartition {
    Get-Partition | Where-Object { $_.Type -eq 'Recovery' } | Remove-Partition -Confirm:$false
}

function Get-StorageInventory {
    $osDiskNumber = (Get-Partition -DriveLetter C).DiskNumber
    $allPhysicalDisks = @(Get-PhysicalDisk)
    $allDisks = @(Get-Disk | Where-Object { $_.BusType -ne 'USB' })

    $ssdList = [System.Collections.Generic.List[PSCustomObject]]::new()
    $hddList = [System.Collections.Generic.List[PSCustomObject]]::new()
    $osDiskObj = $null

    foreach ($disk in $allDisks) {
        $physicalDisk = $allPhysicalDisks | Where-Object { $_.DeviceID -eq $disk.Number.ToString() }
        $type = $physicalDisk.MediaType

        if ([string]::IsNullOrWhiteSpace($type) -or $type -eq 'Unspecified') {
            if ($disk.BusType -eq 'NVMe' -or $disk.FriendlyName -match 'SSD') { $type = 'SSD' }
            else { $type = 'HDD' }
        }

        # SE AGREGA PartitionStyle AL INVENTARIO
        $diskObj = [PSCustomObject]@{
            Number         = $disk.Number
            SizeGB         = [math]::Round($disk.Size / 1GB)
            Type           = $type
            PartitionStyle = $disk.PartitionStyle
        }

        # Separar el disco del SO de los discos adicionales
        if ($disk.Number -eq $osDiskNumber) {
            $osDiskObj = $diskObj
        } elseif ($type -eq 'SSD') {
            $ssdList.Add($diskObj)
        } else {
            $hddList.Add($diskObj)
        }
    }

    return @{
        OSDisk    = $osDiskObj
        ExtraSSDs = @($ssdList)
        ExtraHDDs = @($hddList)
    }
}

function Maximize-Partition {
    param(
        [string]$DriveLetter = 'C'
    )
    $maxSize = (Get-PartitionSupportedSize -DriveLetter $DriveLetter).SizeMax
    Resize-Partition -DriveLetter $DriveLetter -Size $maxSize
}

function Format-SecondaryDataDisk {
    # SE AGREGA EL PARÁMETRO PartitionStyle
    param(
        [int]$DiskNumber,
        [string]$PartitionStyle
    )
    
    Set-Disk -Number $DiskNumber -IsOffline $false -ErrorAction SilentlyContinue
    Set-Disk -Number $DiskNumber -IsReadOnly $false -ErrorAction SilentlyContinue
    Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false -ErrorAction SilentlyContinue
    
    # SE REEMPLAZA EL GPT HARDCODEADO EN CÓDIGO POR LA VARIABLE DINÁMICA
    Initialize-Disk -Number $DiskNumber -PartitionStyle $PartitionStyle -Confirm:$false
    New-Partition -DiskNumber $DiskNumber -UseMaximumSize -DriveLetter D | Format-Volume -FileSystem NTFS -NewFileSystemLabel "Datos" -Confirm:$false | Out-Null
}

function Split-SingleOSDisk {
    param(
        [int]$DiskNumber,
        [int]$SizeGB
    )

    $diskInfo = Get-Disk -Number $DiskNumber
    $partCount = (Get-Partition -DiskNumber $DiskNumber).Count

    if ($SizeGB -le 140) {
        $cSizeGB = $SizeGB - 15
        $crearD = $false
    } elseif ($SizeGB -le 300) {
        $cSizeGB = 120
        $crearD = $true
    } else {
        $cSizeGB = 150
        $crearD = $true
    }

    # VALIDACIÓN MBR
    if ($crearD -and $diskInfo.PartitionStyle -eq 'MBR' -and $partCount -ge 3) {
        Write-Warning "Límite MBR detectado. Maximizando C: y abortando partición D:."
        Maximize-Partition -DriveLetter C
        return
    }

    $maxSize = (Get-PartitionSupportedSize -DriveLetter C).SizeMax
    $targetSize = $cSizeGB * 1GB

    if ($targetSize -gt $maxSize) { $targetSize = $maxSize }

    Resize-Partition -DriveLetter C -Size $targetSize

    if ($crearD) {
        New-Partition -DiskNumber $DiskNumber -UseMaximumSize -DriveLetter D | Format-Volume -FileSystem NTFS -NewFileSystemLabel "Datos" -Confirm:$false | Out-Null
    }
}

# ==============================================================================
# 2. LÓGICA PRINCIPAL (WORKFLOW)
# ==============================================================================

Clear-DriveLetter
Remove-RecoveryPartition

# Mapear todo el hardware disponible
$inventory = Get-StorageInventory

# Procesar según los escenarios de hardware
if ($inventory.ExtraSSDs.Count -gt 0) {
    
    # Escenario 1A: Existe un SSD adicional (Prioridad máxima)
    Maximize-Partition
    Format-SecondaryDataDisk -DiskNumber $inventory.ExtraSSDs[0].Number -PartitionStyle $inventory.OSDisk.PartitionStyle

} elseif ($inventory.ExtraHDDs.Count -gt 0) {
    
    # Escenario 1B: Existe un HDD mecánico adicional (Prioridad media)
    Maximize-Partition
    Format-SecondaryDataDisk -DiskNumber $inventory.ExtraHDDs[0].Number -PartitionStyle $inventory.OSDisk.PartitionStyle

} else {
    
    # Escenario 2: No hay discos adicionales, particionar el disco del SO
    Split-SingleOSDisk -DiskNumber $inventory.OSDisk.Number -SizeGB $inventory.OSDisk.SizeGB

}