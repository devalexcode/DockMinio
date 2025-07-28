# DockMinio - Dominio y SSL (HTTPS) para aplicaciones Docker

![DockMinio](/docs/DockMinio.gif)

**DockMinio** es un script Bash que automatiza la configuración de Caddy como reverse - proxy para aplicaciones Docker lo cual permite de una manera muy sencilla vincular aplicaciones a un dominio y cifrar el tráfico mediante SSL (HTTPS).

## Permite:

1. Detectar contenedores en ejecución y sus puertos expuestos.
2. Vincular un dominio (DNS `A` apuntando a la IP pública) a la aplicación seleccionada.
3. Administrar configuraciones de dominio existentes.

---

## Características:

- Instalación automática de Caddy (si no está presente).
- Listado interactivo de contenedores Docker y puertos.
- Verificación automática del dominio (`HTTP 2xx` o `3xx`).
- Menú interactivo con opciones de “Agregar” y “Eliminar” dominios.

---

## Requisitos previos:

- Sistema operativo: Ubuntu 18.04, 20.04, 22.04, 24.04
- Acceso con usuario que tenga privilegios de sudo
- Contenedores Docker en ejecución
- Acceso al panel de configuración de los DNS de tu dominio

## Contenido del repositorio:

```plaintext
/DockMinio
├── run.sh              # Script que automatiza la instalación.
├── README.md           # Documentación del proyecto
```

## Instalación:

#### 1. Descargar o clonar el repositorio

```bash
git clone https://github.com/devalexcode/DockMinio.git
```

#### 2. Ingresa a la carpeta del proyecto

```bash
cd DockMinio
```

#### 3. Dar permisos de ejecución al script

```bash
chmod +x run.sh
```

#### 4 Ejecutar el script (Requiere permisos root)

```bash
sudo ./run.sh
```

## Agregar Dominio:

![DockMinio - Agregar dominio a contenedor Docker](/docs/DockMinio.gif)

## Eliminar Dominio:

![DockMinio - Eliminar dominio de contenedor Docker](/docs/DockMinio-eliminar.gif)

## 👨‍💻 Autor

Desarrollado por [Alejandro Robles | Devalex ](http://devalexcode.com)  
¿Necesitas que lo haga por ti? ¡Estoy para apoyarte! 🤝 https://devalexcode.com/soluciones/dominio-https-para-tu-aplicacion-docker-en-tu-vps

¿Dudas o sugerencias? ¡Contribuciones bienvenidas!
