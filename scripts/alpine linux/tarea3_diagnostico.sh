#!/bin/ash

# --- COLORES ---
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- FUNCIONES ---

validacionIp() {
    local mensaje=$1
    local ip
    while true; do
        printf "${mensaje}"
        read ip
        # Regex para validar IPv4
        if echo "$ip" | grep -E -q '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'; then
            echo "$ip"
            return 0
        fi
        echo -e "${RED}Formato IPv4 inválido. Reintente.${NC}"
    done
}

GestionarIpFija() {
    echo -e "\n${CYAN}[Verificando Configuración de Red]${NC}"
    # Verifica si la interfaz eth0 tiene dirección por DHCP (buscando en el archivo de interfaces)
    if grep -q "iface eth0 inet dhcp" /etc/network/interfaces; then
        echo -e "${YELLOW}ADVERTENCIA: El servidor tiene DHCP habilitado.${NC}"
        nuevaIp=$(validacionIp "Ingrese la IP estática: ")
        read -p "Ingrese la máscara (ej. 255.255.255.0): " mascara
        gw=$(validacionIp "Ingrese el Gateway: ")

        # Configuración en Alpine
        echo -e "auto lo\niface lo inet loopback\n\nauto eth0\niface eth0 inet static\n  address $nuevaIp\n  netmask $mascara\n  gateway $gw" > /etc/network/interfaces
        rc-service networking restart
        echo -e "${GREEN}IP configurada con éxito.${NC}"
    else
        actual=$(ip addr show eth0 | grep "inet " | awk '{print $2}')
        echo -e "${GREEN}El servidor ya tiene una IP fija: $actual${NC}"
    fi
}

ConfigurarDns() {
    echo -e "\n${BLUE}=== CONFIGURACION DE ZONA Y REGISTROS ===${NC}"
    read -p "Ingrese el nombre de la zona (ej: reprobados.com): " dominio
    [ -z "$dominio" ] && dominio="reprobados.com"

    read -p "Ingrese el hostname (ej: www): " hostname
    [ -z "$hostname" ] && hostname="www"

    ipDestino=$(validacionIp "Ingrese la IP a la que apuntara ${hostname}.${dominio}: ")

    # Crear directorios si no existen
    mkdir -p /etc/bind/zones

    # 1. Agregar zona a named.conf.local si no existe
    if ! grep -q "zone \"$dominio\"" /etc/bind/named.conf.local; then
        echo -e "zone \"$dominio\" {\n  type master;\n  file \"/etc/bind/zones/db.$dominio\";\n};" >> /etc/bind/named.conf.local
        
        # 2. Crear el archivo de zona base
        echo "\$TTL 604800
@   IN  SOA ns1.$dominio. admin.$dominio. ( 1 ; Serial )
@   IN  NS  ns1.$dominio.
ns1 IN  A   127.0.0.1" > /etc/bind/zones/db.$dominio
        echo -e "${GREEN}Zona $dominio creada.${NC}"
    fi

    # 3. Agregar el registro A
    echo "$hostname IN A $ipDestino" >> /etc/bind/zones/db.$dominio
    named-checkconf /etc/bind/named.conf && rc-service named restart
    echo -e "${GREEN}Registro $hostname.$dominio configurado con exito.${NC}"
}

borrarDominio() {
    read -p "Ingrese el dominio que desea borrar: " borrar
    if [ -f "/etc/bind/zones/db.$borrar" ]; then
        rm "/etc/bind/zones/db.$borrar"
        # Eliminar del archivo de configuración (usando sed)
        sed -i "/zone \"$borrar\"/,/};/d" /etc/bind/named.conf.local
        rc-service named restart
        echo -e "${GREEN}Dominio $borrar borrado correctamente.${NC}"
    else
        echo -e "${RED}Error: El dominio no existe.${NC}"
    fi
}

MonitoreoDns() {
    echo -e "\n${CYAN}=== MODULO DE MONITOREO Y VALIDACION ===${NC}"
    if rc-service named status | grep -q "started"; then
        echo -e "${GREEN}[OK] El servicio BIND9 esta operando.${NC}"
    else
        echo -e "${RED}[ERROR] El servicio DNS esta detenido.${NC}"
        return
    }

    read -p "Ingrese el dominio a validar: " dominioTest
    [ -z "$dominioTest" ] && dominioTest="reprobados.com"
    read -p "Ingrese el host (ej: www): " hostTest
    [ -z "$hostTest" ] && hostTest="www"

    nombreCompleto="${hostTest}.${dominioTest}"

    echo -e "${YELLOW}Ejecutando nslookup para $nombreCompleto...${NC}"
    # Usamos nslookup directo a localhost
    ipDevuelta=$(nslookup $nombreCompleto 127.0.0.1 | grep "Address" | tail -n 1 | awk '{print $2}')

    if [ ! -z "$ipDevuelta" ]; then
        echo -e "${GREEN}[EXITO] nslookup resolvió en: $ipDevuelta${NC}"
        
        echo -e "${YELLOW}Ejecutando ping...${NC}"
        if ping -c 1 $nombreCompleto > /dev/null; then
            echo -e "${GREEN}[EXITO] Ping respondió correctamente.${NC}"
            # Evidencia: comparamos con la IP de eth0
            ipLocal=$(ip addr show eth0 | grep "inet " | awk '{print $2}' | cut -d/ -f1)
            if [ "$ipDevuelta" == "$ipLocal" ]; then
                echo -e "${CYAN}EVIDENCIA: La IP coincide con el servidor local ($ipDevuelta).${NC}"
            fi
        fi
    else
        echo -e "${RED}[FALLO] No se pudo resolver.${NC}"
    fi
}

# --- MENU PRINCIPAL ---
while true; do
    echo -e "\n${YELLOW}======================================================================"
    echo -e "                           SERVIDOR DNS (ALPINE)                      "
    echo -e "======================================================================${NC}"
    echo "[1] - VERIFICAR INSTALACION"
    echo "[2] - INSTALAR BIND9"
    echo "[3] - REMOVER BIND9"
    echo "[4] - CONFIGURAR ZONA Y REGISTROS"
    echo "[5] - BORRAR DOMINIO"
    echo "[6] - MONITOREO"
    echo "[7] - SALIR"

    read -p "Ingrese una opción: " opc

    case $opc in
        1) apk info bind | grep -q "bind" && echo -e "${GREEN}Instalado${NC}" || echo -e "${RED}No instalado${NC}" ;;
        2) apk add bind bind-tools && rc-update add named default && rc-service named start ;;
        3) rc-service named stop && apk del bind bind-tools ;;
        4) ConfigurarDns ;;
        5) borrarDominio ;;
        6) MonitoreoDns ;;
        7) break ;;
        *) echo "Opción inválida" ;;
    esac
done