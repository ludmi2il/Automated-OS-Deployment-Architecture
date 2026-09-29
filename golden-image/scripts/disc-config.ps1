# Liberar la letra D: a la fuerza y de forma 100% silenciosa
if (Get-Volume -DriveLetter D -ErrorAction SilentlyContinue) {
    @"
select volume D
assign letter=Z
"@ | diskpart | Out-Null

    # Darle 2 segundos al sistema para que refresque las tablas de rutas
    Start-Sleep -Seconds 2
}

# Obtener el número del disco donde está instalado el sistema operativo (C:)
$osDiskNumber = (Get-Partition -DriveLetter C).DiskNumber

# Consultar el hardware físico una sola vez y forzar array
$allPhysicalDisks = @(Get-PhysicalDisk)

# Obtener todos los discos (incluso Offline), forzando array y excluyendo USB
$allDisks = @(Get-Disk | Where-Object { $_.BusType -ne 'USB' })

# Inicializar listas tipadas de alto rendimiento
$ssdList = [System.Collections.Generic.List[PSCustomObject]]::new()
$hddList = [System.Collections.Generic.List[PSCustomObject]]::new()

# Clasificar discos según su tecnología (SSD / HDD)
foreach ($disk in $allDisks) {
    # Búsqueda instantánea en memoria
    $physicalDisk = $allPhysicalDisks | Where-Object { $_.DeviceID -eq $disk.Number.ToString() }
    $type = $physicalDisk.MediaType
    
    # Fallback por si Windows reporta nulo, blanco o "Unspecified"
    if ([string]::IsNullOrWhiteSpace($type) -or $type -eq 'Unspecified') {
        if ($disk.BusType -eq 'NVMe' -or $disk.FriendlyName -match 'SSD') { 
            $type = 'SSD' 
        } else { 
            $type = 'HDD' 
        }
    }

    $diskObj = [PSCustomObject]@{ Disk = $disk; SizeGB = [math]::Round($disk.Size / 1GB) }

    if ($type -eq 'SSD') {
        $ssdList.Add($diskObj)
    } else {
        $hddList.Add($diskObj)
    }
}

# Eliminar la partición de recuperación que bloquea a C:
Get-Partition | Where-Object { $_.Type -eq 'Recovery' } | Remove-Partition -Confirm:$false

# Separar los discos adicionales forzando la estructura de array
$extraSsdList = @($ssdList | Where-Object { $_.Disk.Number -ne $osDiskNumber })
$extraHddList = @($hddList | Where-Object { $_.Disk.Number -ne $osDiskNumber })

# Determinar cuál será el disco de datos (Prioridad: 1. SSD secundario > 2. HDD)
$dataDiskNumber = $null
if ($extraSsdList.Count -ge 1) {
    $dataDiskNumber = $extraSsdList[0].Disk.Number
} elseif ($extraHddList.Count -ge 1) {
    $dataDiskNumber = $extraHddList[0].Disk.Number
}

# ESCENARIO 1: Existe un disco físico adicional disponible para datos
if ($null -ne $dataDiskNumber) {
    # 1. Extender la unidad C: para que use el 100% de su disco actual
    $maxSizeC = (Get-PartitionSupportedSize -DriveLetter C).SizeMax
    Resize-Partition -DriveLetter C -Size $maxSizeC

    # 2. Inicializar y formatear el disco extra seleccionado como D:
    Set-Disk -Number $dataDiskNumber -IsOffline $false -ErrorAction SilentlyContinue
    Set-Disk -Number $dataDiskNumber -IsReadOnly $false -ErrorAction SilentlyContinue
    Clear-Disk -Number $dataDiskNumber -RemoveData -RemoveOEM -Confirm:$false -ErrorAction SilentlyContinue
    Initialize-Disk -Number $dataDiskNumber -PartitionStyle GPT -Confirm:$false
    New-Partition -DiskNumber $dataDiskNumber -UseMaximumSize -DriveLetter D | Format-Volume -FileSystem NTFS -NewFileSystemLabel "Datos" -Confirm:$false | Out-Null
}
# ESCENARIO 2: Disco único -> Particionado lógico en el disco del SO
else {
    $osDisk = $allDisks | Where-Object { $_.Number -eq $osDiskNumber }
    $sizeGB = [math]::Round($osDisk.Size / 1GB)

    if ($sizeGB -le 140) {
        $cSizeGB = $sizeGB - 15
        $crearD = $false
    } elseif ($sizeGB -le 300) {
        $cSizeGB = 120
        $crearD = $true
    } else {
        $cSizeGB = 150
        $crearD = $true
    }

    $maxSize = (Get-PartitionSupportedSize -DriveLetter C).SizeMax
    $targetSize = $cSizeGB * 1GB
    
    # Prevenir errores si el target excede por unos pocos megas el máximo real
    if ($targetSize -gt $maxSize) { $targetSize = $maxSize }
    
    Resize-Partition -DriveLetter C -Size $targetSize

    if ($crearD) {
        New-Partition -DiskNumber $osDisk.Number -UseMaximumSize -DriveLetter D | Format-Volume -FileSystem NTFS -NewFileSystemLabel "Datos" -Confirm:$false | Out-Null
    }
}