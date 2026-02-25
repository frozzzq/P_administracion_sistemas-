
if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] Este script debe ejecutarse como root."
    exit 1
fi

# Cargar librerias
. "$(dirname "$0")/lib/funcion_ssh.sh"
. "$(dirname "$0")/lib/funcion_dhcp.sh"
. "$(dirname "$0")/lib/funcion_dns.sh"

BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

menu_principal() {
    echo ""
    echo -e "${BLUE}===================================================================${NC}"
    echo -e "${CYAN}             ADMINISTRACION DE ALPINE LINUX                        ${NC}"
    echo -e "${BLUE}===================================================================${NC}"
    echo -e "${YELLOW}1. Gestionar SSH${NC}"
    echo -e "${YELLOW}2. Gestionar DHCP${NC}"
    echo -e "${YELLOW}3. Gestionar DNS${NC}"
    echo -e "${YELLOW}4. Salir${NC}"
}

while true; do
    menu_principal
    printf "Elige una opcion: "
    read opcion

    case "$opcion" in
        1) menu_ssh ;;
        2) menu_dhcp ;;
        3) menu_dns ;;
        4) echo "Saliendo..."; exit 0 ;;
        *) echo -e "${RED}Opcion invalida.${NC}" ;;
    esac

    printf "\n¿Volver al menu? (si/no): "
    read continuar
    [ "$continuar" != "si" ] && break
done