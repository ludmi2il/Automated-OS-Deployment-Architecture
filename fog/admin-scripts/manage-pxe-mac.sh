#!/bin/bash
# Script para administrar excepciones PXE por MAC en Kea DHCP (ABM)

CONF_FILE="/etc/kea/kea-dhcp4.conf"
ACTION=$1
HOSTNAME=$2
MAC=$3
EFI=$4

# ==============================================================================
# 1. DEFINICIÓN DE FUNCIONES
# ==============================================================================

check-dependencies() {
    if ! command -v jq &> /dev/null; then
        echo "Error critico: 'jq' no esta instalado. Ejecuta 'sudo apt install jq'"
        exit 1
    fi
}

show-usage() {
    echo "Error: Faltan parametros o accion invalida."
    echo "Uso para AGREGAR: $0 add <Nombre_Equipo> <MAC_Address> <Archivo_EFI>"
    echo "Uso para BORRAR:  $0 remove <Nombre_Equipo>"
    echo "Uso para LISTAR:  $0 list"
    exit 1
}

list-reservations() {
    echo "=== Reservas PXE Actuales (Kea DHCP) ==="
    jq -r '.Dhcp4.subnet4[0].reservations[]? | "Equipo: \(.hostname) | MAC: \(."hw-address") | EFI: \(."boot-file-name")"' "$CONF_FILE"
    echo "========================================"
}

add-reservation() {
    local name=$1
    local mac=$2
    local efi=$3

    if [ -z "$name" ] || [ -z "$mac" ] || [ -z "$efi" ]; then
        echo "Error: Faltan parametros para crear la reserva."
        echo "Ejemplo: $0 add Taller-AsusZ77 00:1A:2B:3C:4D:5E snponly.efi"
        exit 1
    fi

    # Estandarizar la MAC a minusculas (formato preferido por Kea)
    mac=$(echo "$mac" | tr '[:upper:]' '[:lower:]')

    # Modificación atómica del JSON vía archivo temporal
    jq "(.Dhcp4.subnet4[0].reservations) |= ( ( . // [] ) | map(select(.hostname != \"$name\" and .\"hw-address\" != \"$mac\")) + [{\"hostname\": \"$name\", \"hw-address\": \"$mac\", \"boot-file-name\": \"$efi\"}] )" "$CONF_FILE" > "$CONF_FILE.tmp"

    if [ $? -eq 0 ]; then
        mv "$CONF_FILE.tmp" "$CONF_FILE"
        echo "Exito: Reserva '$name' agregada al archivo de Kea."
        systemctl restart kea-dhcp4-server
        echo "Servicio Kea DHCP reiniciado correctamente."
    else
        echo "Error: Fallo la modificacion estructural del archivo JSON."
        rm -f "$CONF_FILE.tmp"
        exit 1
    fi
}

remove-reservation() {
    local name=$1

    if [ -z "$name" ]; then
        echo "Error: Falta el nombre del equipo a borrar."
        echo "Ejemplo: $0 remove Taller-AsusZ77"
        exit 1
    fi

    jq "(.Dhcp4.subnet4[0].reservations) |= ( ( . // [] ) | map(select(.hostname != \"$name\")) )" "$CONF_FILE" > "$CONF_FILE.tmp"

    if [ $? -eq 0 ]; then
        mv "$CONF_FILE.tmp" "$CONF_FILE"
        echo "Exito: Reserva '$name' eliminada (si existia)."
        systemctl restart kea-dhcp4-server
        echo "Servicio Kea DHCP reiniciado correctamente."
    else
        echo "Error: Fallo la modificacion estructural del archivo JSON."
        rm -f "$CONF_FILE.tmp"
        exit 1
    fi
}

# ==============================================================================
# 2. LÓGICA PRINCIPAL (WORKFLOW)
# ==============================================================================

check-dependencies

case "$ACTION" in
    list)
        list-reservations
        ;;
    add)
        add-reservation "$HOSTNAME" "$MAC" "$EFI"
        ;;
    remove)
        remove-reservation "$HOSTNAME"
        ;;
    *)
        show-usage
        ;;
esac