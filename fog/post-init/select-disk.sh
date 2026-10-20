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
    
    # 0. Override Destructivo
    if [[ "$WIPE_DATA" == "true" ]] || grep -qE "WIPE_DATA=true" /proc/cmdline; then
        echo "-> [FILTRO] ADVERTENCIA: WIPE_DATA=true detectado. Forzando seleccion destructiva en $disk." > /dev/console
        return 0
    fi

    # OPTIMIZACION: Hacemos una sola consulta de I/O al hardware y la guardamos en RAM
    local disk_info
    disk_info=$(blkid ${disk}* 2>/dev/null)

    # 1. Buscamos si existe la particion de datos
    if ! echo "$disk_info" | grep -iq 'LABEL="Datos Locales"'; then
        return 0 # No tiene Datos Locales, es seguro
    fi
    
    # 2. Si la tiene, verificamos si es Hibrido
    if echo "$disk_info" | grep -iqE '(TYPE="vfat"|System Reserved)'; then
        return 0 # Es el disco del SO hibrido, es seguro
    fi
    
    # 3. Disco secundario dedicado
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