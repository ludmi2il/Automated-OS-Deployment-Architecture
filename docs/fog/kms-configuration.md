# ⚙️ Configuración e Inyección del Servidor KMS en FOG Project

Este documento explica cómo configurar la interfaz web de **FOG Project** para inyectar dinámicamente la dirección del servidor KMS en el kernel de Linux (**FOS**) durante el arranque por red (PXE).

---

## 🧠 ¿Cómo funciona la inyección?

Cuando un equipo inicia una tarea de despliegue mediante iPXE, FOG permite anexar parámetros personalizados a la línea de comandos del kernel de Linux (`/proc/cmdline`).

1. **En la fase Post-Download (Linux):** El módulo `inject-kms.sh` intercepta los argumentos del kernel buscando la clave `kmsserver`, extrae su valor y genera el archivo `C:\Windows\Setup\Scripts\kms.env` dentro de la partición de Windows recién volcada.
2. **En la fase Sysprep (Windows):** El script `dynamic-activation.ps1` lee `kms.env` y apunta el cliente de licencias (`slmgr.vbs /skms`) hacia ese servidor de forma desatendida.

> **💡 Flexibilidad de sintaxis (Case-Insensitive):**
> El inyector normaliza automáticamente el nombre de la variable. Podés escribir cualquiera de las siguientes variantes en FOG y serán reconocidas por igual:
> * `kmsserver=kms.tudominio.local`
> * `KMS_SERVER=kms.tudominio.local`
> * `kms_server=192.168.1.50:1688`
> * `kms-server=kms.tudominio.local`

---

## 🛠️ Dónde configurar el argumento en la Web de FOG

Podés definir el parámetro `kmsserver=kms.tudominio.local` en tres niveles según tu necesidad:

| Nivel | Ruta en el panel web de FOG | Campo a completar | Cuándo usarlo |
| :--- | :--- | :--- | :--- |
| **1. Global (Recomendado)** | **FOG Configuration** -> **FOG Settings** -> **General Settings** | `FOG_KERNEL_ARGS` | Aplica a todos los despliegues (incluso equipos no registrados). |
| **2. Por Grupo** | **Groups** -> *(Seleccionar grupo)* -> **General** | `Group Kernel Arguments` | Aplica masivamente a un departamento o laboratorio específico. |
| **3. Por Host** | **Hosts** -> *(Seleccionar equipo)* -> **General** | `Host Kernel Arguments` | Pruebas aisladas o máquinas en otra VLAN/subred. |

---

## 🔄 Comportamiento de Fallback (Si no se configura en FOG)

El sistema está diseñado bajo una arquitectura **tolerante a fallos**. Si olvidás configurar el argumento en FOG:

1. `inject-kms.sh` informará una advertencia en la consola de FOS indicando que no se detectó `kmsserver` y **no creará** el archivo `kms.env`.
2. Durante el primer arranque de Windows, `dynamic-activation.ps1` priorizará primero cualquier **licencia OEM embebida en la BIOS/UEFI** (`OA3xOriginalProductKey`).
3. Si el equipo no posee clave OEM y no existe `kms.env`, el script omitirá la asignación manual (`/skms`) e intentará activar Windows mediante **Auto-descubrimiento DNS (registros SRV `_vlmcs._tcp`)** en el dominio local.

---

<details>
<summary><b>🧪 Avanzado: Pruebas manuales en FOS Debug Mode (Click para expandir)</b></summary>
<br>

Si necesitás probar la inyección por SSH sin ejecutar el despliegue completo de Partclone:

```bash
. /usr/share/fog/lib/funcs.sh
mkdir -p /images && mount -o nolock,proto=tcp "${storageip}:/images" /images
export postdownpath="/images/postdownloadscripts/"
export hd="/dev/sda" osid="9" KMS_SERVER="kms.tudominio.local"

. ${postdownpath}fog.postdownload
```
</details>