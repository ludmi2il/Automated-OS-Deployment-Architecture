#!/bin/bash
# Script para administrar excepciones PXE por MAC en Kea DHCP (ABM)

CONF_FILE="/etc/kea/kea-dhcp4.conf"
ACTION=$1
HOSTNAME=$2

# Verificar que jq este instalado
if ! command -v jq &> /dev/null; then
    echo "Error critico: 'jq' no esta instalado. Ejecuta 'sudo apt install jq'"
    exit 1
fi

# Validar que al menos se haya pasado una accion
if [ -z "$ACTION" ]; then
    echo "Error: Faltan parametros."
    echo "Uso para AGREGAR: $0 add <Nombre_Equipo> <MAC_Address> <Archivo_EFI>"
    echo "Uso para BORRAR:  $0 remove <Nombre_Equipo>"
    echo "Uso para LISTAR:  $0 list"
    exit 1
fi

if [ "$ACTION" == "list" ]; then
    echo "=== Reservas PXE Actuales (Kea DHCP) ==="
    # Navega por el JSON y extrae los datos de la primera subred configurada por FOG
    jq -r '.Dhcp4.subnet4[0].reservations[]? | "Equipo: \(.hostname) | MAC: \(."hw-address") | EFI: \(."boot-file-name")"' "$CONF_FILE"
    echo "========================================"
    exit 0

elif [ "$ACTION" == "add" ]; then
    MAC=$3
    EFI=$4
    
    if [ -z "$HOSTNAME" ] || [ -z "$MAC" ] || [ -z "$EFI" ]; then
        echo "Error: Faltan parametros para crear la reserva."
        echo "Ejemplo: $0 add Taller-AsusZ77 00:1A:2B:3C:4D:5E snponly.efi"
        exit 1
    fi
    
    # Estandarizar la MAC a minusculas (formato preferido por Kea)
    MAC=$(echo "$MAC" | tr '[:upper:]' '[:lower:]')
    
    # 1. Lee el array de reservas de la primera subred (o crea uno vacio si no existe).
    # 2. Elimina cualquier reserva previa que tenga el mismo hostname o la misma MAC para evitar duplicados.
    # 3. Anexa el nuevo objeto JSON con la reserva.
    jq "(.Dhcp4.subnet4[0].reservations) |= ( ( . // [] ) | map(select(.hostname != \"$HOSTNAME\" and .\"hw-address\" != \"$MAC\")) + [{\"hostname\": \"$HOSTNAME\", \"hw-address\": \"$MAC\", \"boot-file-name\": \"$EFI\"}] )" "$CONF_FILE" > "$CONF_FILE.tmp"
    
    if [ $? -eq 0 ]; then
        mv "$CONF_FILE.tmp" "$CONF_FILE"
        echo "Exito: Reserva '$HOSTNAME' agregada al archivo de Kea."
        systemctl restart kea-dhcp4-server
        echo "Servicio Kea DHCP reiniciado correctamente."
    else
        echo "Error: Fallo la modificacion estructural del archivo JSON."
        rm -f "$CONF_FILE.tmp"
        exit 1
    fi

elif [ "$ACTION" == "remove" ]; then
    if [ -z "$HOSTNAME" ]; then
        echo "Error: Falta el nombre del equipo a borrar."
        echo "Ejemplo: $0 remove Taller-AsusZ77"
        exit 1
    fi
    
    # Filtra el array de reservas eliminando el objeto que coincida con el hostname
    jq "(.Dhcp4.subnet4[0].reservations) |= ( ( . // [] ) | map(select(.hostname != \"$HOSTNAME\")) )" "$CONF_FILE" > "$CONF_FILE.tmp"
    
    if [ $? -eq 0 ]; then
        mv "$CONF_FILE.tmp" "$CONF_FILE"
        echo "Exito: Reserva '$HOSTNAME' eliminada (si existia)."
        systemctl restart kea-dhcp4-server
        echo "Servicio Kea DHCP reiniciado correctamente."
    else
        echo "Error: Fallo la modificacion estructural del archivo JSON."
        rm -f "$CONF_FILE.tmp"
        exit 1
    fi

else
    echo "Error: Accion '$ACTION' no reconocida. Usa 'add', 'remove' o 'list'."
    exit 1
fi