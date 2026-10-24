#!/bin/bash
# Post-init script para FOG Project
# Objetivo: Seleccion dinamica (NVMe mas chico -> SSD SATA mas chico -> HDD)
# Filtro: Solo discos >= 60 GiB

# ==============================================================================
# 1. DEFINICION DE FUNCIONES Y LIMITES
# ==============================================================================

# 60 GiB convertidos a sectores de 512 bytes (125.829.120 sectores)
MIN_SECTORS=$((60 * 1024 * 1024 * 2))

is_safe_target() {
    local disk=$1
    
    # 0. Override Destructivo manual o por kernel cmdline
    if [[ "$WIPE_DATA" == "true" ]] || grep -qE "WIPE_DATA=true" /proc/cmdline; then
        echo "-> [FILTRO] ADVERTENCIA: WIPE_DATA=true. Forzando seleccion destructiva en $disk." > /dev/console
        return 0
    fi

    # 1. Guardamos la salida de las herramientas en RAM (optimización I/O en FOG)
    local disk_info lsblk_info sfdisk_info
    disk_info=$(blkid ${disk}* 2>/dev/null)
    lsblk_info=$(lsblk -no LABEL,TYPE,FSTYPE "$disk" 2>/dev/null)
    
    # Si no existe "Datos Locales", es un disco de sistema normal y seguro de sobreescribir
    if ! echo -e "${disk_info}\n${lsblk_info}" | grep -iq 'Datos Locales'; then
        return 0 
    fi
    
    # 2. CAPA ETIQUETAS: Regex multi-idioma (Inglés/Español) y firmas del SO
    local boot_patterns='(TYPE="vfat"|vfat|[Ss]ystem [Rr]eserved|[Rr]eservado|[Bb]oot|Windows|msftdata)'
    if echo -e "${disk_info}\n${lsblk_info}" | grep -iqE "$boot_patterns"; then
        return 0 # Híbrido detectado por etiqueta o filesystem (ej. FAT32 para UEFI)
    fi
    
    # 3. CAPA TABLA DE PARTICIONES: Leemos con sfdisk (nativo en FOG)
    # Busca la marca 'bootable' (MBR) o el UUID estándar de la partición EFI System (GPT)
    sfdisk_info=$(sfdisk -d "$disk" 2>/dev/null)
    if echo "$sfdisk_info" | grep -iqE '(bootable|C12A7328-F81F-11D2-BA4B-00A0C93EC93B)'; then
        return 0 # Híbrido detectado por flags de arranque
    fi
    
    # 4. Es un disco secundario puro
    echo "-> [FILTRO] Omitiendo $disk: Es un disco secundario exclusivo de Datos." > /dev/console
    return 1
}

get_smallest_nvme() {
    local min_size=-1
    local target_disk=""

    for dev in /sys/block/nvme[0-9]n[0-9]*; do
        # 1. Ignorar si no es un directorio valido
        [[ ! -d "$dev" ]] && continue
        
        # 2. Ignorar si no tiene tamaño o es menor a 60GB
        local size=$(cat "$dev/size" 2>/dev/null)
        [[ -z "$size" || "$size" -lt $MIN_SECTORS ]] && continue
        
        # 3. Ignorar si es un disco exclusivo de datos
        is_safe_target "/dev/$(basename "$dev")" || continue
        
        # Si paso todos los filtros, evaluamos si es el mas chico
        if [[ $min_size -eq -1 || $size -lt $min_size ]]; then
            min_size=$size
            target_disk="/dev/$(basename "$dev")"
        fi
    done

    echo "$target_disk"
}

get_smallest_sata_ssd() {
    local min_size=-1
    local target_disk=""

    for dev in /sys/block/sd*; do
        [[ ! -d "$dev" ]] && continue
        
        # 1. Ignorar unidades removibles (USB/SD)
        local removable=$(cat "$dev/removable" 2>/dev/null)
        [[ "$removable" -eq 1 ]] && continue 

        # 2. Ignorar si es mecanico (rotational=1)
        local rotational=$(cat "$dev/queue/rotational" 2>/dev/null)
        [[ "$rotational" -eq 1 ]] && continue 

        # 3. Ignorar tamaño insuficiente
        local size=$(cat "$dev/size" 2>/dev/null)
        [[ -z "$size" || "$size" -lt $MIN_SECTORS ]] && continue
        
        # 4. Ignorar si es inseguro
        is_safe_target "/dev/$(basename "$dev")" || continue
        
        # Asignacion
        if [[ $min_size -eq -1 || $size -lt $min_size ]]; then
            min_size=$size
            target_disk="/dev/$(basename "$dev")"
        fi
    done

    echo "$target_disk"
}

get_smallest_hdd() {
    local min_size=-1
    local target_disk=""

    for dev in /sys/block/sd*; do
        [[ ! -d "$dev" ]] && continue
        
        # 1. Ignorar unidades removibles (USB/SD)
        local removable=$(cat "$dev/removable" 2>/dev/null)
        [[ "$removable" -eq 1 ]] && continue 

        # 2. Ignorar si NO es mecanico (rotational=0)
        local rotational=$(cat "$dev/queue/rotational" 2>/dev/null)
        [[ "$rotational" -eq 0 ]] && continue 

        # 3. Ignorar tamaño insuficiente
        local size=$(cat "$dev/size" 2>/dev/null)
        [[ -z "$size" || "$size" -lt $MIN_SECTORS ]] && continue
        
        # 4. Ignorar si es inseguro
        is_safe_target "/dev/$(basename "$dev")" || continue
        
        # Asignacion
        if [[ $min_size -eq -1 || $size -lt $min_size ]]; then
            min_size=$size
            target_disk="/dev/$(basename "$dev")"
        fi
    done

    echo "$target_disk"
}

resolve_target_disk() {
    local target=""
    
    # 1. Prioridad Absoluta: NVMe
    target=$(get_smallest_nvme)
    if [[ -n "$target" ]]; then
        echo "$target"
        return
    fi

    # 2. Prioridad Media: SATA SSD
    target=$(get_smallest_sata_ssd)
    if [[ -n "$target" ]]; then
        echo "$target"
        return
    fi

    # 3. Fallback: Disco Mecanico mas chico
    target=$(get_smallest_hdd)
    if [[ -n "$target" ]]; then
        echo "$target"
        return
    fi

    echo ""
}

# ==============================================================================
# 2. LOGICA PRINCIPAL (WORKFLOW)
# ==============================================================================

echo "Iniciando escaneo de hardware de almacenamiento a nivel kernel..."

TARGET_DISK=$(resolve_target_disk)

if [[ -n "$TARGET_DISK" ]]; then
    echo "Disco seleccionado por jerarquia y tamano minimo (>= 60GB): $TARGET_DISK"
    
    # Exportamos fdrive para forzar a que la funcion nativa de FOG respete este disco
    export fdrive="$TARGET_DISK"
else
    echo "ERROR CRITICO: No se detecto ningun disco de almacenamiento valido mayor a 60GB."
    sleep 10
fi