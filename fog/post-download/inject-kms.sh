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
    
    # 1. Buscar en variables de entorno locales (util en modo Debug manual)
    KMS_SERVER="${kmsserver:-${KMS_SERVER:-${kms_server:-}}}"
    
    # Leemos los argumentos que iPXE le paso al kernel de Linux al bootear
    for arg in $(cat /proc/cmdline); do
        if [[ "$arg" == *=* ]]; then
            KEY="${arg%%=*}"          # Todo lo que esta ANTES del '='
            VAL="${arg#*=}"           # Todo lo que esta DESPUES del '='
            
            # Pasamos KEY a minusculas (${KEY,,})
            KEY_CLEAN="${KEY,,}"
            KEY_CLEAN="${KEY_CLEAN//[_-]/}" # Limpia tanto guion bajo (_) como guion medio (-)
            
            if [[ "$KEY_CLEAN" == "kmsserver" ]]; then
                KMS_SERVER="$VAL"
            fi
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