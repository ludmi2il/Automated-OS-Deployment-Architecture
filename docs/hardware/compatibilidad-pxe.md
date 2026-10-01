# Registro de Compatibilidad de Hardware y Booteo PXE

Esta tabla documenta las configuraciones de BIOS/UEFI y los binarios de booteo de red requeridos para los diferentes modelos de hardware presentes en el taller de la Facultad.

| Marca / Modelo | Tipo de BIOS | Secure Boot | Archivo de Booteo FOG | Notas Adicionales / Quirks |
| :--- | :--- | :--- | :--- | :--- |
| **Intel Desktop Board 02** | UEFI | Apagado | `ipxe.efi` | Requiere *UEFI Boot* habilitado en BIOS. En FOG, el parámetro *Host BIOS Exit Type* (o global) debe estar forzado en `EXIT` para que pase el arranque al disco local correctamente. |

Este registro es un documento vivo mantenido por el equipo de soporte IT. Su objetivo es documentar las configuraciones exactas necesarias para que los distintos modelos de motherboards de la facultad arranquen correctamente por red (PXE) hacia el entorno FOG.

### 📝 Cómo contribuir a este registro
Si durante un despliegue te encontrás con un modelo de hardware que no está en la lista, por favor agregalo siguiendo estos pasos:
1. Identificá el modelo exacto de la placa madre.
2. Documentá si el booteo exitoso se logró en modo UEFI o Legacy/CSM.
3. Anotá cualquier parámetro especial (quirk) que hayas tenido que modificar en la BIOS o en la interfaz web de FOG para que funcione.