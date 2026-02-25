
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

verificar_ssh() {
    echo ""
    echo -e "${CYAN}--- Verificando estado de OpenSSH Server ---${NC}"

    if rc-service sshd status > /dev/null 2>&1; then
        echo -e "${GREEN}[OK] El servicio sshd esta ACTIVO.${NC}"
    else
        echo -e "${RED}[!!] El servicio sshd esta INACTIVO o no instalado.${NC}"
    fi

    if rc-update show default 2>/dev/null | grep -q "sshd"; then
        echo -e "${GREEN}[OK] sshd esta configurado para iniciar en el BOOT.${NC}"
    else
        echo -e "${RED}[!!] sshd NO esta en el arranque automatico.${NC}"
    fi

    if [ -f /etc/ssh/sshd_config ]; then
        echo -e "${GREEN}[OK] Archivo de configuracion encontrado: /etc/ssh/sshd_config${NC}"
        PUERTO=$(grep "^Port " /etc/ssh/sshd_config | awk '{print $2}')
        if [ -n "$PUERTO" ]; then
            echo "     Puerto configurado: $PUERTO"
        else
            echo "     Puerto por defecto: 22"
        fi
    else
        echo -e "${RED}[!!] Archivo sshd_config no encontrado.${NC}"
    fi
}

instalar_ssh() {
    echo ""
    echo -e "${CYAN}--- Instalacion de OpenSSH Server ---${NC}"

    if apk info openssh-server > /dev/null 2>&1; then
        echo -e "${GREEN}[OK] OpenSSH Server ya esta instalado.${NC}"
    else
        echo "Instalando openssh-server..."
        apk add --no-cache openssh-server
        if [ $? -ne 0 ]; then
            echo -e "${RED}[ERROR] Fallo la instalacion. Verifica tu conexion de red.${NC}"
            return 1
        fi
        echo -e "${GREEN}[OK] openssh-server instalado correctamente.${NC}"
    fi

    if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
        echo "Generando claves del servidor SSH..."
        ssh-keygen -A
        echo -e "${GREEN}[OK] Claves generadas.${NC}"
    fi

    echo "Habilitando inicio automatico en el boot..."
    rc-update add sshd default
    echo -e "${GREEN}[OK] sshd anadido al arranque.${NC}"

    echo "Iniciando el servicio sshd..."
    rc-service sshd start
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[OK] Servicio sshd iniciado.${NC}"
    else
        echo -e "${RED}[ERROR] No se pudo iniciar el servicio.${NC}"
        return 1
    fi

    IP=$(ip addr show eth0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
    [ -z "$IP" ] && IP=$(hostname -I | awk '{print $1}')
    echo ""
    echo -e "${GREEN}SSH listo. Desde el cliente conectate con:${NC}"
    echo -e "${YELLOW}  ssh root@$IP${NC}"
}

desinstalar_ssh() {
    echo ""
    echo -e "${CYAN}--- Desinstalacion de OpenSSH Server ---${NC}"

    if ! apk info openssh-server > /dev/null 2>&1; then
        echo -e "${YELLOW}[INFO] openssh-server no esta instalado. Nada que hacer.${NC}"
        return 0
    fi

    echo "Deteniendo el servicio sshd..."
    rc-service sshd stop 2>/dev/null

    echo "Eliminando del arranque automatico..."
    rc-update del sshd default 2>/dev/null

    echo "Desinstalando openssh-server..."
    apk del openssh-server
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[OK] openssh-server desinstalado correctamente.${NC}"
    else
        echo -e "${RED}[ERROR] No se pudo desinstalar.${NC}"
    fi
}

menu_ssh() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${CYAN}      GESTION DE SERVICIO SSH           ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "${YELLOW}1. Verificar estado de SSH${NC}"
    echo -e "${YELLOW}2. Instalar y configurar SSH${NC}"
    echo -e "${YELLOW}3. Desinstalar SSH${NC}"
    echo -e "${YELLOW}4. Volver al menu principal${NC}"
    printf "Elige una opcion: "
    read op

    case "$op" in
        1) verificar_ssh ;;
        2) instalar_ssh ;;
        3) desinstalar_ssh ;;
        4) return ;;
        *) echo -e "${RED}[ERROR] Opcion invalida.${NC}" ;;
    esac
}