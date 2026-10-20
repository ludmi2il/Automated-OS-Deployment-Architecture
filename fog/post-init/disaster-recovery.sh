#!/bin/bash
# Script: disaster-recovery.sh
# Objetivo: Backup preventivo de tabla de particiones en NFS

# Abortar si el modulo anterior fallo y no hay disco seleccionado
if [[ -z "$fdrive" ]]; then
    echo "-> [DISASTER RECOVERY] Abortado: No hay disco de destino definido (\$fdrive vacio)."
    return
fi

# ==============================================================================
# 1. DEFINICION DE FUNCIONES
# ==============================================================================

get_unique_hw_id() {
    local hw_uuid=$(cat /sys/class/dmi/id/product_uuid 2>/dev/null)
    if [[ -z "$hw_uuid" ]]; then
        echo "$mac" | tr ':' '-' | tr '[:upper:]' '[:lower:]'
    else
        echo "$hw_uuid" | tr '[:upper:]' '[:lower:]'
    fi
}

manage_partition_state() {
    local target_disk=$1
    local hw_id=$(get_unique_hw_id)
    
    local mnt_dir="/tmp/nfs-dev"
    local backup_ram="/tmp/part_table_${hw_id}.txt"
    local backup_nfs="${mnt_dir}/part-backups/${hw_id}.txt"

    echo "-> [DISASTER RECOVERY] Identificador de hardware: $hw_id"
    
    # 1. I/O LOCAL PRIMERO
    local DATOS_PART=$(blkid ${target_disk}* 2>/dev/null | grep -i 'LABEL="Datos Locales"' | cut -d: -f1)

    # 2. RED: Montamos NFS
    mkdir -p "$mnt_dir"
    echo "-> Montando recurso NFS (RW) desde FOG..."
    mount -o nolock,proto=tcp,rsize=32768,wsize=32768 ${storageip}:/images/dev "$mnt_dir"
    mkdir -p "${mnt_dir}/part-backups"
    
    # ==========================================================================
    # 3. Garantiza el desmontaje automatico de NFS sin importar por donde salgamos
    # ==========================================================================
    trap 'umount "$mnt_dir" 2>/dev/null; echo "-> [SISTEMA] Recurso NFS desmontado de forma segura."' RETURN EXIT

    # 3A. OVERRIDE DESTRUCTIVO
    if [[ "$WIPE_DATA" == "true" ]] || grep -qE "WIPE_DATA=true" /proc/cmdline; then
        echo "-> [DISASTER RECOVERY] Limpieza de backups antiguos en NFS..."
        rm -f "$backup_nfs"
        export PART_BACKUP_EXISTS="false"
        return
    fi

    # 3B. ESTADO SANO
    if [[ -n "$DATOS_PART" ]]; then
        echo "-> [ESTADO SANO] Particion 'Datos Locales' detectada en $DATOS_PART."
        sfdisk -d $target_disk | grep "^${DATOS_PART}[[:space:]]" > "$backup_ram"
        cp "$backup_ram" "$backup_nfs"
        
        export PART_BACKUP_EXISTS="true"
        export PART_BACKUP_PATH="$backup_ram"
        return
    fi

    # 3C. ALERTA Y RECUPERACION DE BACKUP ACTIVO
    echo "-> [ALERTA] No se detecto 'Datos Locales' en $target_disk."
    if [[ -f "$backup_nfs" ]]; then
        echo "-> [ACTIVO] Backup encontrado en FOG. Cargando a RAM..."
        cp "$backup_nfs" "$backup_ram"
        
        export PART_BACKUP_EXISTS="true"
        export PART_BACKUP_PATH="$backup_ram"
        return
    fi

    # 3D. FALLBACK ABSOLUTO
    echo "-> No hay backup previo. Despliegue estandar destructivo."
    export PART_BACKUP_EXISTS="false"
    return
}

# ==============================================================================
# 2. EJECUCION PRINCIPAL (WORKFLOW)
# ==============================================================================

# Llamamos a la funcion pasandole la variable global $fdrive definida en select-disk.sh
manage_partition_state "$fdrive"