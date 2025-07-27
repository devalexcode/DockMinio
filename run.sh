#!/usr/bin/env bash
set -euo pipefail

RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
BLUE='\033[38;5;39m'
NC='\e[0m'
BOLD='\033[1m'
CADDYFILE="/etc/caddy/Caddyfile"
# Obtener IP pública (global)
PUBLIC_IP=$(curl -s http://checkip.amazonaws.com || curl -s https://icanhazip.com)
CHECK_DOMAIN_MAX_ATTEMPTS=50

#-------------------------------------------------
# Funciones
#-------------------------------------------------

press_enter() {
    read -rp "Presione [Enter] para continuar..."
}

# Función que recibe el dominio y muestra la tabla estilo mysql
print_domain_table() {
    local domain=$1
    local headers=(TIPO NOMBRE VALOR)
    local row=("A" "$domain" $PUBLIC_IP)
    local w=()

    # 1) Calcular ancho máximo de cada columna
    for i in "${!headers[@]}"; do
        w[i]=${#headers[i]}
        ((${#row[i]} > w[i])) && w[i]=${#row[i]}
    done

    # 2) Línea separadora: +———+———+———+
    local sep='+'
    for wi in "${w[@]}"; do
        sep+="$(printf '%*s' $((wi + 2)) '' | tr ' ' '-')+"
    done

    # 3) Función interna para imprimir una fila
    print_row() {
        printf '|'
        for i in "${!w[@]}"; do
            printf ' %-*s |' "${w[i]}" "$1"
            shift
        done
        printf '\n'
    }

    echo -e "${BOLD}🌐 DA DE ALTA EL REGISTRO DE DNS:${NC}"
    echo -e "En el panel de configuración de tu dominio, agrega este registro para que las solicitudes lleguen ${GREEN}correctamente${NC} a tu aplicación 🐳"

    # 4) Dibujar la tabla
    echo "$sep"
    print_row "${headers[@]}"
    echo "$sep"
    print_row "${row[@]}"
    echo "$sep"
}

tn_list_containers() {
    declare -gA CONTAINERS
    echo -e "${BLUE}=================================================${NC}"
    echo -e "${BLUE}      Aplicaciones 🐳 Docker 🐳 en ejecución:   ${NC}"
    echo -e "${BLUE}=================================================${NC}\n"
    local i=1

    while read -r name; do
        # Extrae TODOS los host‑ports expuestos, sin filtrar por internal port
        mapfile -t ports < <(
            docker port "$name" |
                awk -F '-> ' '/->/ {print $2}' |
                awk -F':' '{print $NF}' |
                sed 's#/tcp##' |
                sort -n |
                uniq
        )

        for port in "${ports[@]}"; do
            # Busca un bloque con reverse_proxy NO comentado
            # y descarta el bloque por defecto ":80"
            domain=$(awk -v port=":${port}" '
                # cuando abrimos un bloque {...}
                /^\s*[^#].+\{/ {
                    in_block=1
                    line=$0
                    sub(/\{.*/, "", line)
                    gsub(/^[ \t]+|[ \t]+$/, "", line)
                    block_domain=line
                    next
                }
                # sólo líneas de reverse_proxy no comentadas,
                # dentro de un bloque cuyo nombre NO sea ":<número>"
                in_block && /^[ \t]*reverse_proxy/ && index($0, port) && block_domain !~ /^:[0-9]+$/ {
                    print block_domain
                    exit
                }
                # fin del bloque }
                in_block && /^\s*}/ {
                    in_block=0
                }
            ' "$CADDYFILE")

            if [[ -n "$domain" ]]; then
                printf "  ${BLUE}%2d)${NC} %s  ->  %s ${GREEN}%s${NC}\n" \
                    "$i" "$name" "$port" "$domain"
            else
                printf "  ${BLUE}%2d)${NC} %s  ->  %s\n" \
                    "$i" "$name" "$port"
            fi

            CONTAINERS[$i]="$name:$port"
            ((i++))
        done
    done < <(docker ps --format '{{.Names}}')

    printf "  ${BOLD}%2d)${NC} %s\n" "0" "<- Regresar al Menu"
}

# Verifica que el dominio responde con 200 o 301. Devuelve "true" o "false".\
verify_domain() {
    local domain=$1
    local sleep=$2
    local url="https://$domain"
    local status=""

    sleep $sleep

    status=$(curl -s --connect-timeout 5 --max-time 10 -o /dev/null -w "%{http_code}" "$url") || status=0

    if [[ "$status" =~ ^[23][0-9]{2}$ ]]; then
        return 0
    else
        return 1
    fi
}

return_menu() {
    # Si no hubo argumento, $1 expandirá a cadena vacía en lugar de error
    local sel="${1:-}"

    # Si sel está vacío O es cero, volvemos al menú
    if [[ -z "$sel" || "$sel" -eq 0 ]]; then
        main
    fi
}

msg_error() {
    local msg=$1
    echo -e "\n${RED}**************************************************************************${NC}"
    echo -e "${RED}ERROR:${NC} $msg ❌"
    echo -e "${RED}**************************************************************************${NC}"
}

msg_done() {
    local msg=$1
    echo -e "\n${GREEN}==================================================================${NC}"
    echo -e "${GREEN}✅ $msg ${NC}"
    echo -e "${GREEN}==================================================================${NC}"
}

msg_exit() {
    read -rp "Presione [Enter] para hacer otra operación o CTRL+C para salir."
    clear
    main
}

print_banner() {
    clear
    echo -e "
▗▄▄▄   ▄▄▄  ▗▞▀▘█  ▄ ▗▖  ▗▖▄ ▄▄▄▄  ▄  ▄▄▄  🐳
▐▌  █ █   █ ▝▚▄▖█▄▀  ▐▛▚▞▜▌▄ █   █ ▄ █   █ 
▐▌  █ ▀▄▄▄▀     █ ▀▄ ▐▌  ▐▌█ █   █ █ ▀▄▄▄▀ 
▐▙▄▄▀           █  █ ▐▌  ▐▌█       █       
    
    ${BOLD}DockMinio${NC} by Alejandro Robles | Devalex
${BLUE}══════════════════════════════════════════════════════════${NC}
Dominio 🌐 y ${GREEN}https://${NC}🔒 para tus aplicaciones Docker 🐳
${BLUE}══════════════════════════════════════════════════════════${NC}"

    if [[ $EUID -ne 0 ]]; then
        msg_error "Este script debe ejecutarse con permisos root (sudo)." >&2
        exit 1
    fi

}

restart_caddy() {
    # 5) Recargar servicio Caddy
    echo -e "\n${BLUE}Configurando Caddy ....... ⚙️${NC}"
    if systemctl reload caddy; then
        echo -e "✅ ${GREEN}Caddy.......... OK${NC}"
    else
        msg_error "Error al recargar Caddy. Revisa la sintaxis del Caddyfile."
        exit 1
    fi
}

msg_confirm() {
    # $1 = mensaje a mostrar
    local msg=${1:-"¿Estás seguro que quieres continuar?"}
    local confirm

    # -r para no interpretar backslashes, -p para prompt
    read -rp "$msg [s/N]: " confirm

    case "$confirm" in
    [sS] | [sS][iI])
        return 0 # confirma
        ;;
    *)
        echo -e "\n---------------------------------------------------------"
        echo -e "operación ${RED}CANCELADA${NC}"
        echo -e "---------------------------------------------------------"
        return 1 # no confirma
        ;;
    esac
}

#---------------------------------------------------------------------
#   Agregar dominios a con
#---------------------------------------------------------------------
admin_containers() {

    clear

    # 1) Listar contenedores y puertos
    tn_list_containers

    # 2) Selección de la aplicación (bucle hasta opción válida)
    while true; do

        echo -e "\n---------------------------------------------------------"
        echo -e "Selecciona la aplicación a vincular a un dominio ${GREEN}https://${NC}"
        echo -e "---------------------------------------------------------"

        read -rp $'Ingresa el número y presiona [Enter] para continuar: ' sel

        return_menu $sel

        if [[ "$sel" =~ ^[0-9]+$ ]] && ((sel >= 1 && sel <= ${#CONTAINERS[@]})); then
            IFS=":" read -r cname cport <<<"${CONTAINERS[$sel]}"
            clear
            echo -e "---------------------------------------------------------"
            echo -e "${GREEN}Has seleccionado:${NC} 🐳 APLICACION: ${BLUE}$cname${NC} PUERTO: ${BLUE}$cport${NC}"
            echo -e "---------------------------------------------------------"
            break
        fi
        clear
        echo -e "${RED}❌ Opción inválida.${NC} Volviendo a listar contenedores..."
        tn_list_containers
    done

    # 3) Ingreso del dominio (bucle hasta dominio válido y disponible)
    while true; do
        read -rp "Ingresa el dominio a configurar (ej. $cname.midominio.com): " domain
        if [[ "$domain" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}$ ]]; then
            if ! verify_domain $domain 1; then
                clear
                msg_done "Dominio disponible."
                break
            else
                msg_error "$domain no es candidato para esta acción."
            fi
        else
            msg_error "Dominio inválido. Asegúrate de ingresar un nombre de dominio válido."
        fi
    done

    print_domain_table $domain

    press_enter

    # 4) Añadir configuración al Caddyfile
    echo -e "$domain {\n    reverse_proxy localhost:$cport\n}" | sudo tee -a "$CADDYFILE" >/dev/null

    restart_caddy

    # 6) Verificar el funcionamiento del dominio
    attempt=1
    valid=0
    while ((attempt <= CHECK_DOMAIN_MAX_ATTEMPTS)); do
        echo -e "Verificando acceso a la aplicación, esto suele durar unos minutos 🌐 ........ (Se paciente, puedes ir probando en tu navegador 🧑‍💻)"

        if verify_domain $domain 15; then
            valid=1
            break
        fi

        attempt=$((attempt + 1))
    done

    # 7) Mostrar respuesta final en HTTPS
    if ((valid)); then
        msg_done "¡Éxito! La aplicación responde correctamente en: https://$domain"
    else
        msg_error "la aplicación no respondió en https://$domain"
    fi

    msg_exit
}

#---------------------------------------------------------------------
#   Eliminar Dominios
#---------------------------------------------------------------------
admin_domains() {

    clear

    list_domains

    # Pide selección al usuario
    while true; do

        echo -e "\n---------------------------------------------------------"
        echo -e "Selecciona el dominio a ${RED}ELIMINAR${NC} 🗑"
        echo -e "---------------------------------------------------------"

        read -rp $'Ingresa el número y presiona [Enter] para continuar: ' sel
        if [ "$sel" -eq 0 ]; then
            main
        fi

        return_menu $sel
        if [[ "$sel" =~ ^[0-9]+$ ]] && ((sel >= 1 && sel <= ${#domains[@]})); then
            break
        fi
        clear
        echo -e "${RED}❌ Opción inválida.${NC} Volviendo a listar dominios..."
        list_domains
    done

    target="${domains[sel - 1]}"

    if msg_confirm; then
        # Elimina el bloque del dominio seleccionado
        awk -v dom="$target" '
  /^\s*[^#].+\{/ {
    line=$0
    sub(/\{.*/, "", line)
    gsub(/^[ \t]+|[ \t]+$/, "", line)
    if (line == dom) { skip=1 }
  }
  skip && /^\s*}/ { skip=0; next }
  skip { next }
  { print }
' "$CADDYFILE" >"${CADDYFILE}.tmp"

        # Sustituye el archivo original
        sudo mv "${CADDYFILE}.tmp" "$CADDYFILE"

        msg_done "Dominio eliminado"

        # Recarga Caddy
        restart_caddy
    fi

    msg_exit
}

list_domains() {
    # Extrae las líneas que definen bloques de sitio (dominios), omitiendo ":80"
    mapfile -t domains < <(
        grep -E '^\s*[^#].+\{' "$CADDYFILE" |
            sed 's/{.*//; s/^\s*//; s/\s*$//' |
            grep -v '^:80$' |
            uniq
    )

    if ((${#domains[@]} == 0)); then
        echo "No se encontraron dominios en funcionamiento."
        msg_exit
    fi

    echo -e "${YELLOW}=================================================${NC}"
    echo -e "${YELLOW}   🌐   Dominios en funcionamiento:   ${NC}"
    echo -e "${YELLOW}=================================================${NC}\n"

    for i in "${!domains[@]}"; do
        num=$((i + 1))
        printf " ${YELLOW}%2d)${NC} %s\n" "$num" "${domains[i]}"
    done

    printf " ${BOLD}%2d)${NC} %s\n" "0" "<- Regresar al Menu"

}

#-------------------------------------------------
# 0) Instalar Caddy si no está instalado
#-------------------------------------------------
check_caddy() {

    if ! command -v caddy >/dev/null 2>&1; then

        echo -e "------------------------------------------------------------------------------------------------------"
        echo -e "¡Vamos a instalar ${GREEN}Caddy${NC} en tu sistema! este actuará como Proxy inverso para tus aplicaciones ${BLUE}Docker 🐳${NC}"
        echo -e "------------------------------------------------------------------------------------------------------\n"

        press_enter

        echo -e "${GREEN}Instalando Caddy...${NC}"

        # Checar si el puerto 80 está ocupado
        if sudo lsof -i :80 -i :443 | grep LISTEN >/dev/null 2>&1; then
            msg_error "El puerto 80 | 443 están en uso, No será posible continuar con la instalación."
        fi

        if command -v apt >/dev/null 2>&1; then
            sudo apt update
            sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg
            # Descargar y guardar la clave
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
            # Agregar el repo usando el keyring
            echo "deb [signed-by=/usr/share/keyrings/caddy-stable-archive-keyring.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" | sudo tee /etc/apt/sources.list.d/caddy-stable.list
            sudo apt update
            sudo apt install -y caddy
            clear
        else
            echo "Gestor de paquetes no soportado. Instala Caddy manualmente e intenta de nuevo." >&2
            exit 1
        fi
    fi

    msg_done "Caddy Proxy instalado"
}

main() {
    print_banner
    echo -e "\n${GREEN}1)${NC} Agregar dominios"
    echo -e "${GREEN}2)${NC} Eliminar dominios"
    echo -e "${GREEN}3)${NC} Salir\n"
    echo -e "${BLUE}══════════════════════════════════════════════════════════${NC}"
    read -rp "Selecciona una opción [1-3]: " opcion

    case "$opcion" in
    1)
        admin_containers
        ;;
    2)
        admin_domains
        ;;
    3)
        exit 0
        ;;
    *)
        clear
        main
        ;;
    esac
}

#-------------------------------------------------
# Flujo principal
#-------------------------------------------------
clear
main
