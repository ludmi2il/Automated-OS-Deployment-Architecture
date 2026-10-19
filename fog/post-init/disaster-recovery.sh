#!/bin/bash
# Script: disaster-recovery.sh
# Objetivo: Backup preventivo de tabla de particiones en NFS

# Abortar si el modulo anterior fallo y no hay disco seleccionado
if [[ -z "$hd" ]]; then
    echo "-> [DISASTER RECOVERY] Abortado: No hay disco de destino definido (\$hd vacio)."
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
    
    # Uso de 'local' para evitar contaminar las variables globales de FOS
    local mnt_dir="/tmp/nfs-dev"
    local backup_ram="/tmp/part_table_${hw_id}.txt"
    local backup_nfs="${mnt_dir}/part-backups/${hw_id}.txt"

    echo "-> [DISASTER RECOVERY] Identificador de hardware: $hw_id"
    mkdir -p "$mnt_dir"

    echo "-> Montando recurso NFS (RW) desde FOG..."
    mount -o nolock,proto=tcp,rsize=32768,wsize=32768 ${storage}:/images/dev "$mnt_dir"
    
    # Si se asigna en Host Custom Variables (WIPE_DATA="true"), eliminamos cualquier backup previo en NFS y forzamos un despliegue totalmente destructivo
    if [[ $WIPE_DATA == "true" ]]; then
        echo "-> [DISASTER RECOVERY] Limpieza de backups antiguos en NFS..."
        rm -f "$backup_nfs"
        export PART_BACKUP_EXISTS="false"
        return
    fi

    # Buscamos qué partición exacta tiene la etiqueta (ej: /dev/nvme0n1p3)
    local DATOS_PART=$(blkid ${target_disk}* | grep -i 'LABEL="Datos Locales"' | cut -d: -f1)

    if [[ -n "$DATOS_PART" ]]; then
        echo "-> [ESTADO SANO] Particion 'Datos Locales' detectada en $DATOS_PART."

        # Extraemos SOLO la línea correspondiente a esta partición de la tabla completa
        sfdisk -d $target_disk | grep "^${DATOS_PART}[[:space:]]" > "$backup_ram"
        cp "$backup_ram" "$backup_nfs"
        
        export PART_BACKUP_EXISTS="true"
    else
        echo "-> [ALERTA] No se detecto 'Datos Locales' en $target_disk."
        if [[ -f "$backup_nfs" ]]; then
            echo "-> [ACTIVO] Backup encontrado en FOG. Cargando a RAM..."
            cp "$backup_nfs" "$backup_ram"
            
            export PART_BACKUP_EXISTS="true"
        else
            echo "-> No hay backup previo. Despliegue estandar destructivo."
            export PART_BACKUP_EXISTS="false"
        fi
    fi

    umount "$mnt_dir"
    
    # Exportamos la ruta para que post-download sepa de donde leer
    export PART_BACKUP_PATH="$backup_ram"
}

# ==============================================================================
# 2. EJECUCION PRINCIPAL (WORKFLOW)
# ==============================================================================

# Llamamos a la funcion pasandole la variable global $hd definida en select-disk.sh
manage_partition_state "$hd"