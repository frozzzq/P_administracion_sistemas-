#!/bin/sh
# =============================================================================
# P7_Prep_Alpine.sh — Prepara el repositorio FTP para la Práctica 7
# Alpine Linux — vsftpd ya instalado (Práctica 5)
# Ejecución única como root desde PuTTY
# =============================================================================

C_RESET='\033[0m'
C_PINK='\033[38;5;213m'
C_ROSE='\033[38;5;218m'
C_HOT='\033[38;5;205m'
C_BOLD='\033[1m'

ok()     { printf "${C_ROSE}[OK]    %s${C_RESET}\n" "$1"; }
info()   { printf "${C_PINK}[INFO]  %s${C_RESET}\n" "$1"; }
warn()   { printf "${C_PINK}[WARN]  %s${C_RESET}\n" "$1"; }
err()    { printf "${C_HOT}[ERROR] %s${C_RESET}\n" "$1"; }
titulo() { printf "\n${C_BOLD}${C_HOT}════════════════════════════════════════${C_RESET}\n"
           printf "${C_BOLD}${C_HOT}  %s${C_RESET}\n" "$1"
           printf "${C_BOLD}${C_HOT}════════════════════════════════════════${C_RESET}\n\n"; }

[ "$(id -u)" -eq 0 ] || { err "Ejecuta como root"; exit 1; }

FTP_USER="ftprepo"
FTP_PASS="Repo123!"
REPO_ROOT="/srv/ftp/users/ftprepo"
REPO_HTTP="$REPO_ROOT/http"

VER_TOMCAT="10.1.34"
VER_NGINX="1.26.2"
VER_APACHE="2.4.62"
TOMCAT_MAJOR="10"

# =============================================================================
# PASO 1 — VERIFICAR VSFTPD
# =============================================================================
titulo "VERIFICANDO VSFTPD"

if ! command -v vsftpd > /dev/null 2>&1; then
    err "vsftpd no instalado. Ejecuta FTP.sh -install primero."
    exit 1
fi
ok "vsftpd disponible"

# Instalar wget si falta
if ! command -v wget > /dev/null 2>&1; then
    info "Instalando wget..."
    apk add --no-cache wget > /dev/null 2>&1 && ok "wget instalado"
fi

# =============================================================================
# PASO 2 — CREAR USUARIO ftprepo SI NO EXISTE
# =============================================================================
titulo "USUARIO ftprepo"

if ! getent passwd "$FTP_USER" > /dev/null 2>&1; then
    info "Creando usuario $FTP_USER..."
    adduser -D -h "$REPO_ROOT" -s /sbin/nologin "$FTP_USER" 2>/dev/null
    printf '%s\n%s\n' "$FTP_PASS" "$FTP_PASS" | passwd "$FTP_USER" > /dev/null 2>&1
    ok "Usuario $FTP_USER creado | Contraseña: $FTP_PASS"
else
    ok "Usuario $FTP_USER ya existe"
fi

# Quitar ftprepo de la lista de bloqueo si estuviera
if [ -f /etc/vsftpd/user_list ]; then
    sed -i "/^${FTP_USER}$/d" /etc/vsftpd/user_list
    ok "ftprepo desbloqueado en user_list"
fi

# =============================================================================
# PASO 3 — CREAR ESTRUCTURA DE CARPETAS
# =============================================================================
titulo "CREANDO ESTRUCTURA /http/Linux/"

# Raíz del chroot: root:root 755 (vsftpd lo exige)
mkdir -p "$REPO_ROOT"
chown root:root "$REPO_ROOT"
chmod 755 "$REPO_ROOT"

# Carpetas del repositorio
for dir in \
    "$REPO_HTTP/Linux/Apache" \
    "$REPO_HTTP/Linux/Nginx"  \
    "$REPO_HTTP/Linux/Tomcat"
do
    mkdir -p "$dir"
    ok "Creada: ${dir#$REPO_ROOT}"
done

chown -R "$FTP_USER:$FTP_USER" "$REPO_HTTP"
chmod -R 755 "$REPO_HTTP"
ok "Permisos aplicados"

# =============================================================================
# PASO 4 — DESCARGAR INSTALADORES
# =============================================================================
titulo "DESCARGANDO INSTALADORES"

descargar() {
    _desc="$1"; _dest="$2"; _url1="$3"; _url2="${4:-}"
    info "Descargando $_desc ..."
    if wget -q --show-progress --timeout=30 "$_url1" -O "$_dest" 2>&1 \
       && [ -s "$_dest" ] \
       && ! head -c 20 "$_dest" 2>/dev/null | grep -qi "<!DOCTYPE\|<html"; then
        ok "$_desc descargado"
        return 0
    fi
    rm -f "$_dest"
    if [ -n "$_url2" ]; then
        warn "Intentando mirror alternativo..."
        if wget -q --show-progress --timeout=30 "$_url2" -O "$_dest" 2>&1 \
           && [ -s "$_dest" ] \
           && ! head -c 20 "$_dest" 2>/dev/null | grep -qi "<!DOCTYPE\|<html"; then
            ok "$_desc descargado (mirror 2)"
            return 0
        fi
        rm -f "$_dest"
    fi
    warn "$_desc NO descargado — agrégalo manualmente en: $_dest"
    return 1
}

descargar \
    "Apache httpd ${VER_APACHE}" \
    "$REPO_HTTP/Linux/Apache/httpd-${VER_APACHE}.tar.gz" \
    "https://archive.apache.org/dist/httpd/httpd-${VER_APACHE}.tar.gz" \
    "https://dlcdn.apache.org/httpd/httpd-${VER_APACHE}.tar.gz"

descargar \
    "Nginx ${VER_NGINX}" \
    "$REPO_HTTP/Linux/Nginx/nginx-${VER_NGINX}.tar.gz" \
    "https://nginx.org/download/nginx-${VER_NGINX}.tar.gz"

descargar \
    "Tomcat ${VER_TOMCAT}" \
    "$REPO_HTTP/Linux/Tomcat/apache-tomcat-${VER_TOMCAT}.tar.gz" \
    "https://archive.apache.org/dist/tomcat/tomcat-${TOMCAT_MAJOR}/v${VER_TOMCAT}/bin/apache-tomcat-${VER_TOMCAT}.tar.gz" \
    "https://dlcdn.apache.org/tomcat/tomcat-${TOMCAT_MAJOR}/v${VER_TOMCAT}/bin/apache-tomcat-${VER_TOMCAT}.tar.gz"

# =============================================================================
# PASO 5 — GENERAR SHA256
# =============================================================================
titulo "GENERANDO SHA256"

for dir in \
    "$REPO_HTTP/Linux/Apache" \
    "$REPO_HTTP/Linux/Nginx"  \
    "$REPO_HTTP/Linux/Tomcat"
do
    for f in "$dir"/*; do
        [ -f "$f" ] || continue
        echo "$f" | grep -q "\.sha256$" && continue
        sha256sum "$f" | awk '{print $1}' > "${f}.sha256"
        ok "$(basename $f).sha256 generado"
    done
done

# =============================================================================
# PASO 6 — REINICIAR VSFTPD
# =============================================================================
titulo "REINICIANDO VSFTPD"

rc-service vsftpd restart > /dev/null 2>&1
sleep 2

if rc-service vsftpd status > /dev/null 2>&1; then
    ok "vsftpd activo"
else
    err "vsftpd no arrancó. Revisa: tail -20 /var/log/vsftpd.log"
    exit 1
fi

# =============================================================================
# RESUMEN
# =============================================================================
IP=$(ip -4 addr show eth2 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
[ -z "$IP" ] && IP=$(ip -4 addr show 2>/dev/null \
    | awk '/inet / && !/127\./ && !/10\.0\.2\./{print $2}' \
    | cut -d/ -f1 | head -1)

printf "\n${C_ROSE}${C_BOLD}════════════════════════════════════════${C_RESET}\n"
printf "${C_ROSE}${C_BOLD}  REPOSITORIO FTP LISTO${C_RESET}\n"
printf "${C_ROSE}${C_BOLD}════════════════════════════════════════${C_RESET}\n\n"
printf "  IP adaptador puente : %s\n" "${IP:-<no detectada>}"
printf "  Usuario FTP         : %s\n" "$FTP_USER"
printf "  Contraseña          : %s\n" "$FTP_PASS"
printf "\n  Estructura:\n"
printf "  /http/Linux/\n"
for dir in Apache Nginx Tomcat; do
    printf "    ├── %s/\n" "$dir"
    for f in "$REPO_HTTP/Linux/$dir"/*; do
        [ -f "$f" ] || continue
        echo "$f" | grep -q "\.sha256$" && continue
        printf "    │     ├── %s\n" "$(basename $f)"
        printf "    │     └── %s.sha256\n" "$(basename $f)"
    done
done
printf "\n${C_PINK}  Ahora ejecuta: sh Main_P7_Alpine.sh${C_RESET}\n\n"