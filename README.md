# Automated OS Deployment Architecture (FOG Project)



Arquitectura de despliegue masivo y automatizado de sistemas operativos diseñada para entornos de soporte técnico con restricciones de red (DHCP protegido).



## 🎯 Contexto y Motivación (Problem Statement)

Actualmente, el aprovisionamiento de equipos en el taller se realiza de forma manual utilizando unidades USB multiboot (Ventoy). Este método presenta varios cuellos de botella operativos:
* **Lentitud en el despliegue:** Los tiempos de booteo e instalación están limitados por el ancho de banda del puerto y la memoria USB.
* **Falta de escalabilidad:** El formateo en simultáneo depende de la cantidad de pendrives físicos disponibles.
* **Intervención manual:** Requiere que un técnico configure parámetros iniciales equipo por equipo.

Esta solución basada en **FOG Project (PXE Boot)** nace para reemplazar las unidades USB, permitiendo el despliegue desatendido de múltiples equipos en simultáneo a través de la red LAN, reduciendo drásticamente los tiempos de instalación y la intervención manual.


## 📊 Arquitectura de Hardware y Almacenamiento

El servidor principal ha sido migrado de un entorno virtualizado a hardware físico dedicado (Intel i3, 4GB RAM) para maximizar las velocidades de despliegue. 

El almacenamiento primario (SSD 240GB) cuenta con un particionamiento optimizado para FOG:
* `/` (Raíz): 20 GB para SO y base de datos MariaDB.
* `swap`: 4 GB para respaldo de memoria durante alta concurrencia de compresión.
* `/images`: ~215 GB (Punto de montaje exclusivo) para el alojamiento principal de las Golden Images.
* `HDD 1TB` (Secundario): Destinado a almacenamiento en frío y respaldos vía Samba (WIP).

## 🕸️ Topología de Red Aislada (Network Topology)

Para evitar interferencias y colisiones con el servidor DHCP corporativo de la Universidad, se implementó una topología aislada utilizando un Router de borde físico que realiza NAT hacia la red institucional:

### 1. Router de Borde (Gigabit LAN)
* **Puerto WAN (Red Institucional):** Configurado como **Dynamic IP (DHCP Client)**. Solicita IP al servidor de la Facultad para obtener salida a internet.
* **Puertos LAN (Red del Taller):** Configurado con IP estática **`192.168.10.1`**. Actúa como Puerta de Enlace (Gateway) para el entorno aislado.
* **Servicio DHCP Interno:** **APAGADO (Disabled)** para ceder el control al servidor FOG.

### 2. Servidor FOG (Debian XFCE)
* **Interfaz Única (LAN):** Conectada a los puertos LAN del Router. 
* **IP Estática:** **`192.168.10.2/24`** configurada de forma manual (`nmtui`).
* **Gateway y DNS:** `192.168.10.1` (Para enrutamiento a través del Router).
* **Servicios Activos:** `isc-dhcp-server` (Entrega IPs al taller, inyecta la puerta de enlace `192.168.10.1` y la orden de booteo PXE), TFTP y NFS.

### 3. Equipos Clientes (Bare Metal)
Se conectan vía Ethernet directamente a los puertos LAN del Router TP-Link. Reciben su IP e instrucciones de booteo desde `192.168.10.2` y el router procesa el NAT para que salgan a Internet a través de su puerta de enlace `192.168.10.1`.



## 🚀 Componentes Clave (Key Components)

1. **Servidor FOG (Debian):** Gestión de imágenes, TFTP y almacenamiento NFS.

2. **Despliegue Desatendido:** Integración con Windows Sysprep y scripts de automatización (Batch, PowerShell) (`SetupComplete.cmd`) para la configuración dinámica de almacenamiento secundario (SSD/HDD), instalación de software adicional y activación de Windows.

3. **Aislamiento de Red:** Prevención de colisiones de DHCP corporativo.



## 🛠️ Scripts de Automatización (Automation Scripts)

En la carpeta `/scripts` se encuentra la lógica para la detección dinámica de unidades de almacenamiento basada en estado sólido o mecánico, asegurando un particionamiento robusto sin importar el orden de enumeración de la placa madre.

## 🏗️ Entorno de Construcción (Build Environment)

Para garantizar un sistema base limpio y libre de controladores residuales, la preparación de la **Golden Image** (modo auditoría, Sysprep) y el testing preliminar de los scripts se realizan íntegramente en máquinas virtuales utilizando **Microsoft Hyper-V**. Una vez que la imagen es sellada y capturada por el servidor FOG, se procede al despliegue masivo hacia los equipos físicos (Bare Metal) del taller.

## 🔮 Roadmap y Próximas Mejoras (Next Steps)

> 🚧 **Work In Progress (WIP):** Los scripts de automatización se encuentran actualmente en fase de pruebas en el laboratorio virtual y físico. Paralelamente, la arquitectura continuará iterando hacia las siguientes mejoras:
* **Almacenamiento en Frío (Samba)**
* **Implementación de FOG Snapins**
* **Inyección dinámica de Drivers**
* **Despliegue de FOG Client para integración automatizada con Active Directory**

## 📘 Documentación Técnica
* [*Procedimiento de creación y generalización de la Golden Image*](docs/preparacion-golden-image.md)
* [*Estructura del archivo unattend.xml*](sysprep/unattend.xml)

## 🔗 Referencias y Recursos Externos

Este proyecto se apoya en las siguientes herramientas open-source y utilidades de la comunidad:

* **[FOG Project](https://fogproject.org/)**: Proyecto principal de clonación y despliegue masivo de imágenes por red (PXE). 
  * *Consulta la [Documentación Oficial de FOG](https://docs.fogproject.org/) para parámetros avanzados del kernel y configuraciones del servidor DHCP.*
* **[Windows Unattend Generator](https://schneegans.de/windows/unattend-generator/)**: Generador web de archivos de respuesta utilizado para construir el `unattend.xml`. Esta herramienta fue fundamental para automatizar la fase OOBE (Out-Of-Box Experience), forzar la creación de cuentas locales y realizar el bypass de los bloqueos de red en Windows 11.


