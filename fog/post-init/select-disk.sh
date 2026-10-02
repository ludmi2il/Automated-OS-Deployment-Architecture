#!/bin/bash
# Post-init script para FOG Project
# Objetivo: Seleccion dinamica (NVMe mas chico -> SSD SATA mas chico -> HDD)

# ==============================================================================
# 1. DEFINICION DE FUNCIONES
# ==============================================================================

get_smallest_nvme() {
    local min_size=-1
    local target_disk=""

    for dev in /sys/block/nvme[0-9]n[0-9]*; do
        if [[ -d "$dev" ]]; then
            local size=$(cat "$dev/size" 2>/dev/null)
            if [[ -n "$size" ]]; then
                if [[ $min_size -eq -1 ]] || [[ $size -lt $min_size ]]; then
                    min_size=$size
                    target_disk="/dev/$(basename "$dev")"
                fi
            fi
        fi
    done

    echo "$target_disk"
}

get_smallest_sata_ssd() {
    local min_size=-1
    local target_disk=""

    for dev in /sys/block/sd*; do
        if [[ -d "$dev" ]]; then
            # Saltear unidades removibles (Pendrives, SD)
            local removable=$(cat "$dev/removable" 2>/dev/null)
            [[ "$removable" -eq 1 ]] && continue 

            local rotational=$(cat "$dev/queue/rotational" 2>/dev/null)
            if [[ "$rotational" -eq 0 ]]; then
                local size=$(cat "$dev/size" 2>/dev/null)
                if [[ -n "$size" ]]; then
                    if [[ $min_size -eq -1 ]] || [[ $size -lt $min_size ]]; then
                        min_size=$size
                        target_disk="/dev/$(basename "$dev")"
                    fi
                fi
            fi
        fi
    done

    echo "$target_disk"
}

get_smallest_hdd() {
    local min_size=-1
    local target_disk=""

    for dev in /sys/block/sd*; do
        if [[ -d "$dev" ]]; then
            # Saltear unidades removibles
            local removable=$(cat "$dev/removable" 2>/dev/null)
            [[ "$removable" -eq 1 ]] && continue 

            local rotational=$(cat "$dev/queue/rotational" 2>/dev/null)
            if [[ "$rotational" -eq 1 ]]; then
                local size=$(cat "$dev/size" 2>/dev/null)
                if [[ -n "$size" ]]; then
                    if [[ $min_size -eq -1 ]] || [[ $size -lt $min_size ]]; then
                        min_size=$size
                        target_disk="/dev/$(basename "$dev")"
                    fi
                fi
            fi
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
    echo "Disco seleccionado por jerarquia y tamano minimo: $TARGET_DISK"
    
    # Exportar la variable para que el motor de FOG la procese
    export hd="$TARGET_DISK"
else
    echo "ERROR CRITICO: No se detecto ningun disco de almacenamiento valido."
    sleep 10
fi