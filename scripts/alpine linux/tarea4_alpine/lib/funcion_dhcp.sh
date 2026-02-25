
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
GRAY='\033[0;37m'
NC='\033[0m'

validacionIpDhcp() {
    local mensaje=$1
    local opcional=$2
    while true; do
        printf "${CYAN}%s${NC}" "$mensaje" >&2
        read ip
        if [ "$opcional" = "true" ] && [ -z "$ip" ]; then echo ""; return 0; fi

        if echo "$ip" | grep -E -q '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'; then
            if echo "$ip" | grep -q '\.0[0-9]'; then
                echo -e "${RED}error: no se permiten ceros a la izquierda${NC}" >&2
                continue
            fi
            primerOcteto=$(echo $ip | cut -d. -f1)
            if [ "$ip" = "0.0.0.0" ]; then echo -e "${RED}error: 0.0.0.0 reservada${NC}" >&2
            elif [ "$ip" = "255.255.255.255" ]; then echo -e "${RED}error: Global Broadcast${NC}" >&2
            elif [ "$primerOcteto" -eq 127 ]; then echo -e "${RED}error: Rango Loopback${NC}" >&2
            elif [ "$primerOcteto" -ge 224 ]; then echo -e "${RED}error: IP Multicast o Reservada${NC}" >&2
            else
                echo "$ip"
                return 0
            fi
        else
            echo -e "${RED}formato ipv4 invalido. reintente${NC}" >&2
        fi
    done
}

verificarInstalacionDhcp() {
    echo -e "${YELLOW}Verificando la instalacion DHCP...${NC}"
    if [ -f "/usr/sbin/kea-dhcp4" ]; then
        echo -e "${GREEN}SERVICIO KEA-DHCP4 INSTALADO${NC}"
    else
        echo -e "${RED}SERVICIO KEA-DHCP4 NO INSTALADO${NC}"
        echo -e "${YELLOW}sugerencia!... use la opcion de instalar el servicio${NC}"
    fi
}

instalacionDhcp() {
    echo -e "${CYAN}INICIANDO INSTALACION...${NC}"
    if [ -f "/usr/sbin/kea-dhcp4" ]; then
        echo -e "${GREEN}SERVICIO KEA-DHCP4 YA INSTALADO, no es necesario reinstalar.${NC}"
    else
        apk add kea-dhcp4
        if [ $? -eq 0 ]; then
            mkdir -p /var/lib/kea
            echo -e "${GREEN}SERVICIO KEA-DHCP4 INSTALADO CON EXITO!${NC}"
        else
            echo -e "${RED}error al instalar${NC}"
        fi
    fi
}

desinstalacionDhcp() {
    echo -e "${MAGENTA}INICIANDO DESINSTALACION...${NC}"
    if [ -f "/usr/sbin/kea-dhcp4" ]; then
        echo -e "${YELLOW}deteniendo proceso en memoria...${NC}"
        rc-service kea-dhcp4 stop 2>/dev/null
        apk del kea-dhcp4
        echo -e "${GREEN}desinstalacion exitosa!${NC}"
    else
        echo -e "${RED}servicio no instalado, no se puede desinstalar${NC}"
    fi
}

configuracionDhcp() {
    echo -e "${BLUE}===CONFIGURACION DEL SERVICIO KEA DHCP===${NC}"

    printf "Ingrese un nombre para el scope: "
    read nombreScope

    rangoI=$(validacionIpDhcp "IP Inicial del rango (Fija para Servidor eth1): ")
    prefijoI=$(echo $rangoI | cut -d. -f1-3)

    # DNS primario = IP del propio servidor
    dnsServidor=$rangoI
    echo -e "${CYAN}DNS primario asignado automaticamente al servidor: $dnsServidor${NC}"

    echo -e "${YELLOW}Configurando la IP fija del servidor ($rangoI)...${NC}"
    ip addr add $rangoI/24 dev eth1 2>/dev/null
    ip link set eth1 up 2>/dev/null

    ultimo=$(echo $rangoI | cut -d. -f4)
    rangoDhcpInicio="$prefijoI.$((ultimo + 1))"

    while true; do
        rangoF=$(validacionIpDhcp "IP final del rango: ")
        prefijoF=$(echo $rangoF | cut -d. -f1-3)
        ultimoF=$(echo $rangoF | cut -d. -f4)

        if [ $ultimo -ge $ultimoF ]; then
            echo -e "${RED}Error: La IP inicial no puede ser mayor a la final${NC}"
        elif [ "$prefijoI" != "$prefijoF" ]; then
            echo -e "${RED}Error: Deben pertenecer a la misma subred ($prefijoI.x)${NC}"
        else
            redId="$prefijoI.0"
            break
        fi
    done

    # DNS secundario opcional
    printf "${YELLOW}Ingrese IP del DNS Secundario (Opcional, ENTER para saltar): ${NC}"
    read dns2

    if [ -n "$dns2" ]; then
        dns_config="$dnsServidor, $dns2"
        echo -e "${GREEN}DNS configurado: primario=$dnsServidor secundario=$dns2${NC}"
    else
        dns_config="$dnsServidor"
        echo -e "${GREEN}DNS configurado: primario=$dnsServidor${NC}"
    fi

    printf "Ingrese la IP del gateway (ENTER para saltar): "
    read gateway

    printf "Ingrese tiempo de concesion en segundos (ej: 28800): "
    read tiempolease
    [ -z "$tiempolease" ] && tiempolease="28800"

    OPT_GW=""
    if [ -n "$gateway" ]; then
        OPT_GW=", { \"name\": \"routers\", \"data\": \"$gateway\" }"
    fi

    echo -e "${BLUE}Generando archivo /etc/kea/kea-dhcp4.conf...${NC}"
    mkdir -p /etc/kea
    cat > /etc/kea/kea-dhcp4.conf <<CONF
{
"Dhcp4": {
    "interfaces-config": { "interfaces": [ "eth1" ] },
    "lease-database": {
        "type": "memfile",
        "persist": true,
        "name": "/var/lib/kea/kea-leases4.csv"
    },
    "valid-lifetime": $tiempolease,
    "subnet4": [
        {
            "id": 1,
            "subnet": "$redId/24",
            "pools": [ { "pool": "$rangoDhcpInicio - $rangoF" } ],
            "option-data": [
                { "name": "domain-name-servers", "data": "$dns_config" }$OPT_GW
            ]
        }
    ]
}
}
CONF

    rc-service kea-dhcp4 restart
    rc-update add kea-dhcp4 default
    echo -e "${GREEN}Configuracion exitosa para el scope: $nombreScope${NC}"
}

monitoreoDhcp() {
    echo -e "${BLUE}================== MONITOREO DHCP ==================${NC}"
    if rc-service kea-dhcp4 status | grep -q "started"; then
        echo -e "estado del servicio: ${GREEN}Running${NC}"
    else
        echo -e "${RED}el servicio dhcp no esta iniciado${NC}"
        return
    fi
    echo "----------------------------------------------------"
    echo -e "${YELLOW}Equipos conectados (Leases):${NC}"
    if [ -f /var/lib/kea/kea-leases4.csv ]; then
        cat /var/lib/kea/kea-leases4.csv | column -t -s ','
    else
        echo -e "${GRAY}no hay equipos conectados actualmente${NC}"
    fi
}

menu_dhcp() {
    echo -e "${BLUE}================== MENU DHCP ==================${NC}"
    echo -e "${YELLOW}1. Verificar instalacion${NC}"
    echo -e "${YELLOW}2. Instalar servicio${NC}"
    echo -e "${YELLOW}3. Desinstalar servicio${NC}"
    echo -e "${YELLOW}4. Configuracion DHCP${NC}"
    echo -e "${YELLOW}5. Monitoreo de servicio${NC}"
    echo -e "${YELLOW}6. Volver al menu principal${NC}"

    printf "Ingrese una opcion: "
    read opcion

    case $opcion in
        1) verificarInstalacionDhcp ;;
        2) instalacionDhcp ;;
        3) desinstalacionDhcp ;;
        4) configuracionDhcp ;;
        5) monitoreoDhcp ;;
        6) return ;;
        *) echo -e "${RED}opcion invalida!${NC}" ;;
    esac
}