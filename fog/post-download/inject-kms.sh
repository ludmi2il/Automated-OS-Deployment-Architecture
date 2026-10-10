#!/bin/bash
# ==============================================================================
# Inyector de KMS dinamico (.env)
# Recibe como parametro $1 la ruta donde esta montado Windows.
# ==============================================================================

TARGET_MNT=$1
SCRIPTS_DIR="${TARGET_MNT}/Windows/Setup/Scripts"

echo "   [KMS] Buscando directorio de trabajo en: $SCRIPTS_DIR"

if [[ -d "$SCRIPTS_DIR" ]]; then
    ENV_FILE="${SCRIPTS_DIR}/kms.env"
    KMS_SERVER=""
    
    # Leemos los argumentos que iPXE le paso al kernel de Linux al bootear
    for arg in $(cat /proc/cmdline); do
        if [[ $arg == kmsserver=* ]]; then
            # Extraemos lo que esta despues del signo igual
            KMS_SERVER="${arg#*=}"
        fi
    done
    
    if [[ -n "$KMS_SERVER" ]]; then
        echo "   [KMS] Argumento kmsserver detectado en el kernel: $KMS_SERVER"
        echo "   [KMS] Generando archivo de configuracion al vuelo..."
        
        echo "KMS_SERVER=${KMS_SERVER}" > "$ENV_FILE"
        
        echo "   [KMS] EXITOSO -> $ENV_FILE creado."
    else
        echo "   [KMS] ERROR CRITICO -> No se detecto el argumento 'kmsserver=' en el kernel de FOS."
    fi
else
    echo "   [KMS] ERROR CRITICO -> No se encontro la carpeta $SCRIPTS_DIR en la imagen."
fi