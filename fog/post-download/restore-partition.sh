#!/bin/bash
# Script: restore-partition.sh
# Objetivo: Re-inyectar SOLO la partición de Datos Locales sin afectar el OS

restore_from_memory() {
    echo "-> [DISASTER RECOVERY] Verificando retencion de Datos Locales..."

    if [[ "$PART_BACKUP_EXISTS" == "true" ]]; then
        if [[ -f "$PART_BACKUP_PATH" ]]; then
            echo "-> [RESTAURACION] Backup quirurgico encontrado: $PART_BACKUP_PATH"
            
            # Inyectamos la particion al esquema actual usando --append
            # Esto añade la particion D: al final sin modificar las fronteras de C:
            sfdisk --append $hd < "$PART_BACKUP_PATH" > /dev/null 2>&1
            
            if [[ $? -eq 0 ]]; then
                echo "-> [EXITO] Particion inyectada correctamente en la tabla de bloques."
                
                # Obligamos al kernel de Linux a releer la tabla actualizada
                sync
                partprobe $hd 2>/dev/null || blockdev --rereadpt $hd 2>/dev/null
                sleep 2 
            else
                echo "-> [ERROR CRITICO] sfdisk --append fallo. Posible solapamiento de sectores."
            fi
        else
            echo "-> [ERROR] PART_BACKUP_EXISTS es true, pero falta el archivo $PART_BACKUP_PATH"
        fi
    else
        echo "-> No hay Datos Locales para retener. Se mantiene esquema nativo."
    fi
}

# ==============================================================================
# 2. EJECUCION PRINCIPAL (WORKFLOW)
# ==============================================================================
restore_from_memory