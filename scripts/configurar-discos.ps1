# Obtener todos los discos en línea
$allDisks = Get-Disk | Where-Object { $_.OperationalStatus -eq 'Online' }
$ssdList = @()
$hddList = @()

# Clasificar discos según su tecnología (SSD / HDD)
foreach ($disk in $allDisks) {
    $physicalDisk = Get-PhysicalDisk | Where-Object { $_.DeviceID -eq $disk.Number.ToString() }
    $type = $physicalDisk.MediaType
    
    # Fallback por si el bus es NVMe o el nombre explícito indica SSD
    if (-not $type) {
        if ($disk.BusType -eq 'NVMe' -or $disk.FriendlyName -match 'SSD') { 
            $type = 'SSD' 
        } else { 
            $type = 'HDD' 
        }
    }

    if ($type -eq 'SSD') {
        $ssdList += [PSCustomObject]@{ Disk = $disk; SizeGB = [math]::Round($disk.Size / 1GB) }
    } else {
        $hddList += [PSCustomObject]@{ Disk = $disk; SizeGB = [math]::Round($disk.Size / 1GB) }
    }
}

# Eliminar la partición de recuperación que bloquea a C:
Get-Partition | Where-Object { $_.Type -eq 'Recovery' } | Remove-Partition -Confirm:$false

# ESCENARIO 1: Hay un SSD para el SO y un HDD independiente para datos
if ($ssdList.Count -ge 1 -and $hddList.Count -ge 1) {
    $dataDiskNumber = $hddList[0].Disk.Number

    # 1. Extender la unidad C: para que use el 100% del SSD principal
    $maxSizeC = (Get-PartitionSupportedSize -DriveLetter C).SizeMax
    Resize-Partition -DriveLetter C -Size $maxSizeC

    # 2. Inicializar el HDD libre
    Set-Disk -Number $dataDiskNumber -IsOffline $false -IsReadOnly $false -ErrorAction SilentlyContinue
    Clear-Disk -Number $dataDiskNumber -RemoveData -RemoveOEM -Confirm:$false -ErrorAction SilentlyContinue
    Initialize-Disk -Number $dataDiskNumber -PartitionStyle GPT -Confirm:$false
    New-Partition -DiskNumber $dataDiskNumber -UseMaximumSize -DriveLetter D | Format-Volume -FileSystem NTFS -NewFileSystemLabel "Datos" -Confirm:$false
}
# ESCENARIO 2: Disco único (Solo un SSD o solo un HDD) -> Particionado lógico
else {
    $singleDisk = $allDisks[0]
    $sizeGB = [math]::Round($singleDisk.Size / 1GB)

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
    Resize-Partition -DriveLetter C -Size ($cSizeGB * 1GB)

    if ($crearD) {
        New-Partition -DiskNumber $singleDisk.Number -UseMaximumSize -DriveLetter D | Format-Volume -FileSystem NTFS -NewFileSystemLabel "Datos" -Confirm:$false
    }
}