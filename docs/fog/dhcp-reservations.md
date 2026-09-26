# Gestión de Excepciones PXE (MAC Reservations)

En entornos de hardware heterogéneo, ciertas placas base antiguas (ej. ASUS Z77) presentan conflictos de interrupciones al recibir el binario nativo `ipxe.efi`. Para estos casos, es necesario inyectar un controlador intermediario (`snponly.efi` o `undionly.kpxe`) de forma exclusiva para la dirección MAC del equipo afectado.

En las versiones modernas de FOG Project, el servicio de asignación de red recae sobre **Kea DHCP**. Dado que Kea utiliza un archivo de configuración estructurado en formato estricto JSON (`/etc/kea/kea-dhcp4.conf`), la edición manual del archivo principal es altamente riesgosa y puede corromper el servicio. 

Para gestionar las excepciones de forma segura, se diseñó un script de automatización que utiliza el procesador JSON `jq`.

## 1. Requisitos Previos en el Servidor FOG

El script depende de la herramienta `jq` para leer, validar e inyectar configuraciones en el archivo de Kea sin romper su sintaxis. Si no se encuentra instalada en el servidor Debian, debe instalarse con:

```bash
sudo apt update
sudo apt install jq
```

## 2. Script de Automatización (ABM)

El personal de soporte debe utilizar este script para consultar, agregar o dar de baja reservas rápidamente desde la terminal sin riesgo de romper la sintaxis del archivo de configuración principal de Kea.

*Nota sobre el Hostname:* El parámetro `<Nombre_Equipo>` es una etiqueta de uso interno para el servidor DHCP, diseñada para organizar el archivo JSON. No modifica el nombre real del sistema operativo en Windows. Se recomienda usar nombres descriptivos sin espacios (ej. `Mesa1-AsusZ77`).

**Uso del script:**
*(Requiere privilegios de administrador `root` para modificar la configuración en `/etc/kea/` y reiniciar el servicio DHCP)*
```bash
# Listar todas las reservas actuales:
sudo ./manage-pxe-mac.sh list

# Agregar una nueva reserva:
sudo ./manage-pxe-mac.sh add <Nombre_Equipo> <MAC_Address> <Archivo_EFI>

# Eliminar una reserva existente:
sudo ./manage-pxe-mac.sh remove <Nombre_Equipo>
```

🔗 **[Ver el código fuente del script aquí](../../fog/admin-scripts/manage-pxe-mac.sh)**