
set -eu


BLUE='\033[0;34m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m' 
NC='\033[0m'


LAB_IFACE="eth1"
ZONEDIR="/var/bind"
NAMED_CONF="/etc/bind/named.conf"
NAMED_LOCAL="/etc/bind/named.conf.local"


log(){ echo -e "${GREEN}[INFO]${NC} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; }
die(){ echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

require_root(){ [ "$(id -u)" -eq 0 ] || die "Ejecuta como root."; }


validacionIp() {
  while true; do
    printf "%s" "$1" >&2
    read -r ip || true
    if echo "$ip" | grep -Eq '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'; then
      echo "$ip"; return 0
    fi
    echo -e "${RED}Formato IPv4 inválido. Reintente.${NC}" >&2
  done
}

server_ip_eth1() {
  ip -4 addr show "$LAB_IFACE" 2>/dev/null | awk '/inet /{print $2}' | head -n1 | cut -d/ -f1 || true
}

verificar_ip_lab() {
  echo -e "${BLUE}================== VALIDACIÓN DE LAB ==================${NC}"
  ip link show "$LAB_IFACE" >/dev/null 2>&1 || die "No existe $LAB_IFACE."
  ip link set "$LAB_IFACE" up 2>/dev/null || true

  SIP="$(server_ip_eth1)"
  if [ -z "${SIP:-}" ]; then
    warn "eth1 NO tiene IP. Configura primero la red estática."
    return 1
  fi
  log "Servidor (eth1) tiene IP: $SIP"
  return 0
}


verificar_instalacion() {
  echo -e "${BLUE}>>> Verificando instalación DNS...${NC}"
  if command -v named >/dev/null 2>&1; then
    log "BIND instalado."
  else
    warn "BIND NO instalado."
  fi
}

instalar_dns() {
  echo -e "${BLUE}================== INSTALAR DNS ==================${NC}"
  if command -v named >/dev/null 2>&1; then
    log "BIND ya está instalado."
    return 0
  fi
  apk add --no-cache bind bind-tools bind-openrc || die "Falló la descarga."
  log "Instalación exitosa."
}

desinstalar_dns() {
  echo -e "${BLUE}================== DESINSTALAR DNS ==================${NC}"
  rc-service named stop 2>/dev/null || true
  apk del bind bind-tools bind-openrc || die "Falló desinstalación."
  log "BIND eliminado del sistema."
}

asegurar_base_bind() {
  mkdir -p /etc/bind "$ZONEDIR"
  [ -f "$NAMED_LOCAL" ] || echo "// Zonas locales" > "$NAMED_LOCAL"
  if [ ! -f "$NAMED_CONF" ]; then
    cat > "$NAMED_CONF" <<EOF
options {
  directory "$ZONEDIR";
  listen-on { any; };
  allow-query { any; };
  recursion no;
};
include "$NAMED_LOCAL";
EOF
  fi
}

zona_existe() { grep -Eq "zone[[:space:]]+\"$1\"" "$NAMED_LOCAL" 2>/dev/null; }

listar_dominios() {
  echo -e "${BLUE}================== DOMINIOS ACTUALES ==================${NC}"
  [ -f "$NAMED_LOCAL" ] || { echo "(vacio)"; return 0; }
  awk -F\" '/zone "/{print " -> " $2}' "$NAMED_LOCAL" | sort -u
}

alta_dominio() {
  echo -e "${BLUE}================== ALTA DE DOMINIO ==================${NC}"
  verificar_ip_lab || return 1
  instalar_dns
  asegurar_base_bind

  printf "Nombre del dominio: "
  read -r DOM
  [ -n "${DOM:-}" ] || return 1

  IPDEST="$(validacionIp "IP de destino para $DOM: ")"
  ZFILE="$ZONEDIR/db.$DOM"

  if ! zona_existe "$DOM"; then
   
    echo "" >> "$NAMED_LOCAL"
    cat >> "$NAMED_LOCAL" <<EOF
zone "$DOM" {
    type master;
    file "$ZFILE";
};
EOF
    log "Zona $DOM agregada a named.conf.local"
  fi

 
  if [ ! -f "$ZFILE" ]; then
    SIP="$(server_ip_eth1)"
    cat > "$ZFILE" <<EOF
\$TTL 3600
@ IN SOA ns1.$DOM. admin.$DOM. ( $(date +%Y%m%d)01 3600 900 1209600 3600 )
@   IN NS ns1.$DOM.
ns1 IN A  $SIP
@   IN A  $IPDEST
www IN A  $IPDEST
EOF
  fi

  if named-checkconf "$NAMED_CONF"; then
      rc-service named restart
      echo -e "${GREEN}ÉXITO: $DOM configurado y servicio reiniciado.${NC}"
  else
      echo -e "${RED}ERROR: Sintaxis inválida en $NAMED_LOCAL. Revisa el archivo.${NC}"
      return 1
  fi
}

baja_dominio() {
  echo -e "${BLUE}================== BAJA DE DOMINIO ==================${NC}"
  listar_dominios
  printf "Dominio a borrar: "
  read -r DOM
  [ -n "${DOM:-}" ] || return 1

  if zona_existe "$DOM"; then
    sed -i "/zone \"$DOM\"/,/};/d" "$NAMED_LOCAL"
    rm -f "$ZONEDIR/db.$DOM"
    rc-service named restart
    echo -e "${YELLOW}Dominio $DOM eliminado.${NC}"
  fi
}

estado_dns() {
  echo -e "${BLUE}================== ESTADO DNS ==================${NC}"
  rc-service named status 2>/dev/null || echo "Servicio detenido."
  listar_dominios
}


menu() {
  echo -e "\n${BLUE}====================================================${NC}"
  echo -e "${YELLOW}               SERVIDOR DNS - ALPINE                ${NC}"
  echo -e "${BLUE}====================================================${NC}"
  echo -e "${GREEN}[1]${NC} Verificar IP (eth1)"
  echo -e "${GREEN}[2]${NC} Verificar instalación"
  echo -e "${GREEN}[3]${NC} Instalar DNS"
  echo -e "${GREEN}[4]${NC} Desinstalar DNS"
  echo -e "${GREEN}[5]${NC} Listar dominios"
  echo -e "${GREEN}[6]${NC} Alta de dominio"
  echo -e "${GREEN}[7]${NC} Baja de dominio"
  echo -e "${GREEN}[8]${NC} Estado del servicio"
  echo -e "${GREEN}[9]${NC} Salir"
}


require_root
while true; do
  menu
  printf "\n${YELLOW}Seleccione una opción: ${NC}"
  read -r op

  case "$op" in
    1) verificar_ip_lab ;;
    2) verificar_instalacion ;;
    3) instalar_dns ;;
    4) desinstalar_dns ;;
    5) listar_dominios ;;
    6) alta_dominio ;;
    7) baja_dominio ;;
    8) estado_dns ;;
    9) exit 0 ;;
    *) echo "Opción no válida." ;;
  esac

  printf "\n${GREEN}¿Volver al menú? (si/no): ${NC}"
  read -r ch
  [ "$ch" = "si" ] || break
done