#!/bin/bash
# Post-init script para FOG Project
# Objetivo: Seleccion dinamica (NVMe mas chico > SSD SATA mas chico > HDD)

echo "Iniciando escaneo de hardware de almacenamiento..."

get_target_disk() {
    local min_nvme_size=-1
    local nvme_disk=""
    local min_ssd_size=-1
    local ssd_disk=""
    local hdd_disk=""

    # 1. Escaneo de NVMe (Prioridad Absoluta)
    for dev in /sys/block/nvme[0-9]n[0-9]*; do
        if [[ -d "$dev" ]]; then
            local disk_name=$(basename "$dev")
            local size=$(cat "$dev/size")

            if [[ $min_nvme_size -eq -1 ]] || [[ $size -lt $min_nvme_size ]]; then
                min_nvme_size=$size
                nvme_disk="/dev/$disk_name"
            fi
        fi
    done

    if [[ -n "$nvme_disk" ]]; then
        echo "$nvme_disk"
        return
    fi

    # 2. Escaneo de SATA/SAS/USB (sdX)
    for dev in /sys/block/sd*; do
        if [[ -d "$dev" ]]; then
            local disk_name=$(basename "$dev")
            local rotational=$(cat "$dev/queue/rotational")
            local size=$(cat "$dev/size")

            if [[ "$rotational" -eq 0 ]]; then
                # Es estado solido
                if [[ $min_ssd_size -eq -1 ]] || [[ $size -lt $min_ssd_size ]]; then
                    min_ssd_size=$size
                    ssd_disk="/dev/$disk_name"
                fi
            else
                # Es mecanico
                if [[ -z "$hdd_disk" ]]; then
                    hdd_disk="/dev/$disk_name"
                fi
            fi
        fi
    done

    # 3. Retornos de fallback
    if [[ -n "$ssd_disk" ]]; then
        echo "$ssd_disk"
    elif [[ -n "$hdd_disk" ]]; then
        echo "$hdd_disk"
    else
        echo ""
    fi
}

TARGET_DISK=$(get_target_disk)

if [[ -n "$TARGET_DISK" ]]; then
    echo "Disco seleccionado por jerarquia y tamano minimo: $TARGET_DISK"
    export hd="$TARGET_DISK"
else
    echo "ERROR CRITICO: No se detecto ningun disco de almacenamiento valido."
    sleep 10
fi