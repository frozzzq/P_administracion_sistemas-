#!/bin/sh
# =============================================================================
# Main_P7_Alpine.sh — Práctica 7 — Alpine Linux
# Instala Apache, Nginx y Tomcat con SSL/TLS
# Fuente: WEB (apk) o FTP (repositorio privado local — ftprepo@127.0.0.1)
#
# - Sin IP fija en ninguna parte — usa variables HTTP del servidor
# - Puerto HTTPS lo elige el usuario → 3 servicios sin conflicto
# - Funciona con cualquier IP (casa, escuela, lo que sea)
# - Idempotente → reinstala las veces que necesites
#
# Uso : sh Main_P7_Alpine.sh  (como root, sin sudo)
# Deps: lib/utils.sh  lib/http_functions.sh
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

for lib in utils.sh http_functions.sh; do
    if   [ -f "$SCRIPT_DIR/lib/$lib" ]; then . "$SCRIPT_DIR/lib/$lib"
    elif [ -f "$SCRIPT_DIR/$lib"     ]; then . "$SCRIPT_DIR/$lib"
    else echo "ERROR: No se encontro $lib"; exit 1
    fi
done

verificar_root

# =============================================================================
# CONFIG — FTP local (vsftpd de Alpine, práctica 5)
# =============================================================================
FTP_SERVER="127.0.0.1"
FTP_USER="ftprepo"
FTP_PASS="Repo123!"
FTP_RUTA="/http/Linux"
TMP_P7="/tmp/p7_descargas"
SSL_DIR="/etc/ssl/practica7"

ARCHIVO_DESCARGADO=""

# =============================================================================
# FUNCIÓN: IP del adaptador puente (solo para mostrarla en el resumen)
# NO se usa dentro de ninguna configuración de servidor
# =============================================================================
obtener_ip_info() {
    _ip=$(ip -4 addr show eth2 2>/dev/null \
        | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
    [ -z "$_ip" ] && _ip=$(ip -4 addr show 2>/dev/null \
        | awk '/inet / && !/127\./ && !/10\.0\.2\./{print $2}' \
        | cut -d/ -f1 | head -1)
    echo "${_ip:-<IP no detectada>}"
}

# =============================================================================
# FUNCIÓN: Pedir puerto HTTPS al usuario
# =============================================================================
pedir_puerto_https() {
    _ph="$1"
    while true; do
        printf "\n${C_PINK}Puerto HTTPS (distinto al $_ph, ej: 443, 8443, 9443): ${C_RESET}"
        read _p
        echo "$_p" | grep -qE '^[0-9]+$' \
            || { print_warning "Debe ser un número"; continue; }
        [ "$_p" -ge 1 ] && [ "$_p" -le 65535 ] \
            || { print_warning "Fuera de rango (1-65535)"; continue; }
        [ "$_p" = "$_ph" ] \
            && { print_warning "No puede ser igual al puerto HTTP"; continue; }
        if ss -tlnp 2>/dev/null | grep -q ":${_p} " || \
           netstat -tlnp 2>/dev/null | grep -q ":${_p} "; then
            print_warning "Puerto $_p ocupado — elige otro"; continue
        fi
        PUERTO_HTTPS="$_p"
        print_success "Puerto HTTPS: $PUERTO_HTTPS"
        return 0
    done
}

# =============================================================================
# FUNCIÓN: Cliente FTP dinámico
# =============================================================================
cliente_ftp() {
    _base="ftp://${FTP_SERVER}${FTP_RUTA}"

    print_title "REPOSITORIO FTP — Linux"
    print_info "Conectando a ftp://${FTP_SERVER}${FTP_RUTA} ..."

    if ! curl -s --connect-timeout 5 \
              -u "${FTP_USER}:${FTP_PASS}" \
              "${_base}/" --list-only > /dev/null 2>&1; then
        print_warning "No se puede conectar al FTP local."
        print_info "Verifica: rc-service vsftpd status"
        return 1
    fi

    _servicios=$(curl -s -u "${FTP_USER}:${FTP_PASS}" \
        "${_base}/" --list-only 2>/dev/null \
        | grep -v "^\." | grep -v "^$")

    [ -z "$_servicios" ] && {
        print_warning "Repositorio vacío. Ejecuta P7_Prep_Alpine.sh primero."
        return 1
    }

    print_success "Servicios disponibles:"
    printf "\n"
    _i=1
    echo "$_servicios" | while IFS= read -r _s; do
        printf "  ${C_WHITE}[%d]${C_RESET} %s\n" "$_i" "$_s"
        _i=$((_i+1))
    done

    _total=$(echo "$_servicios" | grep -c .)
    printf "\n${C_PINK}Selecciona el servicio [1-${_total}]: ${C_RESET}"
    read _sel

    echo "$_sel" | grep -qE '^[0-9]+$' \
        && [ "$_sel" -ge 1 ] && [ "$_sel" -le "$_total" ] \
        || { print_warning "Selección inválida"; return 1; }

    _servicio=$(echo "$_servicios" | sed -n "${_sel}p")
    print_success "Servicio: $_servicio"

    _ruta="${_base}/${_servicio}/"
    _archivos=$(curl -s -u "${FTP_USER}:${FTP_PASS}" \
        "$_ruta" --list-only 2>/dev/null \
        | grep -v "\.sha256$" | grep -E "\.(tar\.gz|tgz|zip)$")

    [ -z "$_archivos" ] && {
        print_warning "No hay instaladores en $_ruta"
        return 1
    }

    printf "\n"; print_success "Versiones disponibles:"; printf "\n"
    _i=1
    echo "$_archivos" | while IFS= read -r _f; do
        printf "  ${C_WHITE}[%d]${C_RESET} %s\n" "$_i" "$_f"
        _i=$((_i+1))
    done

    _total_a=$(echo "$_archivos" | grep -c .)
    printf "\n${C_PINK}Selecciona la versión [1-${_total_a}]: ${C_RESET}"
    read _sela

    echo "$_sela" | grep -qE '^[0-9]+$' \
        && [ "$_sela" -ge 1 ] && [ "$_sela" -le "$_total_a" ] \
        || { print_warning "Selección inválida"; return 1; }

    _archivo=$(echo "$_archivos" | sed -n "${_sela}p")
    mkdir -p "$TMP_P7"
    _dest="$TMP_P7/$_archivo"

    print_info "Descargando $_archivo ..."
    curl -u "${FTP_USER}:${FTP_PASS}" "${_ruta}${_archivo}" \
         -o "$_dest" --progress-bar 2>&1 \
         || { print_warning "Error al descargar"; return 1; }
    print_success "Descargado: $_dest"

    _dest_hash="${_dest}.sha256"
    if curl -s -u "${FTP_USER}:${FTP_PASS}" \
            "${_ruta}${_archivo}.sha256" -o "$_dest_hash" 2>/dev/null \
       && [ -s "$_dest_hash" ]; then
        print_title "VERIFICANDO INTEGRIDAD (SHA256)"
        _hcalc=$(sha256sum "$_dest" | awk '{print $1}')
        _hesp=$(awk '{print $1}' "$_dest_hash" | head -1)
        print_info "Calculado : $_hcalc"
        print_info "Esperado  : $_hesp"
        if [ "$_hcalc" = "$_hesp" ]; then
            print_success "✓ Archivo íntegro — hash SHA256 verificado"
        else
            print_warning "✗ Hash no coincide"
            printf "${C_PINK}¿Continuar de todas formas? [s/N]: ${C_RESET}"
            read _cont
            echo "$_cont" | grep -qiE '^s$' || return 1
        fi
    else
        print_warning "No se encontró .sha256 — se omite verificación"
    fi

    ARCHIVO_DESCARGADO="$_dest"
    print_success "Listo: $ARCHIVO_DESCARGADO"
    return 0
}

# =============================================================================
# FUNCIÓN: Generar certificado SSL autofirmado
# CN = * (wildcard) para que funcione con cualquier IP
# =============================================================================
generar_cert() {
    _nombre="$1"
    _cert="$SSL_DIR/certs/${_nombre}.crt"
    _key="$SSL_DIR/private/${_nombre}.key"

    mkdir -p "$SSL_DIR/certs" "$SSL_DIR/private"
    chmod 700 "$SSL_DIR/private"
    command -v openssl > /dev/null 2>&1 \
        || apk add --no-cache openssl > /dev/null 2>&1

    print_info "Generando certificado SSL para ${_nombre}..."

    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$_key" -out "$_cert" \
        -subj "/C=MX/ST=Sinaloa/L=LosMochis/O=Reprobados/OU=IT/CN=reprobados.com" \
        2>/dev/null \
        || { print_warning "Error generando certificado"; return 1; }

    chmod 600 "$_key"; chmod 644 "$_cert"
    print_success "Cert: $_cert"
    print_success "Key : $_key"
    CERT_FILE="$_cert"
    KEY_FILE="$_key"
}

# =============================================================================
# FUNCIÓN: Configurar Apache con HTTPS
#
# CLAVE: La redirección usa %{HTTP_HOST} — esto significa que Apache
# captura el host con el que llegó la petición (sea 192.168.1.84,
# 172.20.10.5, o cualquier otra IP) y redirige a esa misma IP:PUERTO_HTTPS.
# Sin IP hardcodeada. Funciona con cualquier IP sin tocar nada.
# =============================================================================
ssl_apache() {
    _ph="$1"   # puerto HTTP
    _ps="$2"   # puerto HTTPS

    print_title "APACHE — SSL/TLS (HTTP:${_ph} → HTTPS:${_ps})"

    # Instalar módulo SSL si falta
    apk info -e apache2-ssl > /dev/null 2>&1 \
        || apk add --no-cache apache2-ssl > /dev/null 2>&1

    generar_cert "apache" || return 1

    # Limpiar líneas que versiones anteriores del script pudieron agregar
    sed -i '/LoadModule ssl_module/d'     /etc/apache2/httpd.conf
    sed -i '/LoadModule rewrite_module/d' /etc/apache2/httpd.conf
    sed -i '/LoadModule headers_module/d' /etc/apache2/httpd.conf
    # apache2-ssl ya agrega Listen para HTTPS — evitar duplicado
    sed -i "/^Listen ${_ps}$/d"           /etc/apache2/httpd.conf

    _docroot=$(grep "^DocumentRoot" /etc/apache2/httpd.conf 2>/dev/null \
               | head -1 | awk '{print $2}' | tr -d '"')
    _docroot="${_docroot:-/var/www/localhost/htdocs}"

    # %{HTTP_HOST} = la IP o nombre con el que llegó la petición
    # Así funciona sin importar qué IP tenga el servidor en ese momento
    cat > /etc/apache2/conf.d/p7-ssl.conf << EOF
# Redireccion HTTP → HTTPS
# %{HTTP_HOST} captura la IP real de la peticion sin hardcodearla
<VirtualHost *:${_ph}>
    Redirect permanent / https://%{HTTP_HOST}:${_ps}/
</VirtualHost>

# HTTPS — escucha en cualquier IP del servidor
<VirtualHost *:${_ps}>
    DocumentRoot "${_docroot}"

    SSLEngine on
    SSLCertificateFile    ${CERT_FILE}
    SSLCertificateKeyFile ${KEY_FILE}
    SSLProtocol           TLSv1.2 TLSv1.3
    SSLCipherSuite        HIGH:!aNULL:!MD5

    <Directory "${_docroot}">
        Options -Indexes -FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
</VirtualHost>
EOF

    iptables -A INPUT -p tcp --dport "$_ps" -j ACCEPT 2>/dev/null || true

    if ! httpd -t 2>/dev/null; then
        print_warning "Error de sintaxis — ejecuta: httpd -t"
        httpd -t 2>&1
        return 1
    fi

    rc-service apache2 restart 2>/dev/null; sleep 2

    if rc-service apache2 status > /dev/null 2>&1; then
        print_success "✓ Apache con HTTPS activo en puerto ${_ps}"
    else
        print_warning "Apache no arrancó — revisa: tail -20 /var/log/apache2/error.log"
        return 1
    fi
}

# =============================================================================
# FUNCIÓN: Configurar Nginx con HTTPS
#
# CLAVE: $host en Nginx = la IP o nombre con el que llegó la petición.
# Sin IP hardcodeada. Funciona con cualquier IP.
# =============================================================================
ssl_nginx() {
    _ph="$1"
    _ps="$2"

    print_title "NGINX — SSL/TLS (HTTP:${_ph} → HTTPS:${_ps})"

    generar_cert "nginx" || return 1
    iptables -A INPUT -p tcp --dport "$_ps" -j ACCEPT 2>/dev/null || true

    # $host = la IP real de la petición en el momento que llega
    cat > /etc/nginx/http.d/default.conf << EOF
# Redireccion HTTP → HTTPS
# \$host captura la IP real de la peticion sin hardcodearla
server {
    listen ${_ph};
    server_name _;
    return 301 https://\$host:${_ps}\$request_uri;
}

# HTTPS — escucha en cualquier IP del servidor
server {
    listen ${_ps} ssl;
    server_name _;
    root /var/www/html;
    index index.html;

    ssl_certificate     ${CERT_FILE};
    ssl_certificate_key ${KEY_FILE};
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    add_header X-Frame-Options        "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff"    always;

    location / { try_files \$uri \$uri/ =404; }
    location ~ /\\. { deny all; }
}
EOF

    if nginx -t 2>&1 | grep -q "successful"; then
        print_success "Configuración Nginx válida"
    else
        print_warning "Error en nginx.conf:"
        nginx -t
        return 1
    fi

    rc-service nginx restart 2>/dev/null; sleep 2

    if rc-service nginx status > /dev/null 2>&1; then
        print_success "✓ Nginx con HTTPS activo en puerto ${_ps}"
    else
        print_warning "Nginx no arrancó — revisa: tail -20 /var/log/nginx/error.log"
        return 1
    fi
}

# =============================================================================
# FUNCIÓN: Configurar Tomcat con HTTPS
# Idempotente — elimina conector anterior antes de agregar el nuevo
# =============================================================================
ssl_tomcat() {
    _ph="$1"
    _ps="$2"

    print_title "TOMCAT — SSL/TLS (HTTP:${_ph} → HTTPS:${_ps})"

    [ -d /opt/tomcat ] \
        || { print_warning "Tomcat no instalado en /opt/tomcat"; return 1; }

    generar_cert "tomcat" || return 1

    _ks="/opt/tomcat/conf/tomcat.p12"
    _kspass="tomcat123"

    rm -f "$_ks"
    openssl pkcs12 -export \
        -in "$CERT_FILE" -inkey "$KEY_FILE" \
        -out "$_ks" -name tomcat \
        -passout pass:"$_kspass" 2>/dev/null \
        || { print_warning "Error creando keystore"; return 1; }
    chown tomcat:tomcat "$_ks"; chmod 600 "$_ks"
    print_success "Keystore: $_ks"

    [ "$_ps" -lt 1024 ] && \
        sysctl -w net.ipv4.ip_unprivileged_port_start="$_ps" > /dev/null 2>&1 \
        || true
    iptables -A INPUT -p tcp --dport "$_ps" -j ACCEPT 2>/dev/null || true

    cp /opt/tomcat/conf/server.xml /opt/tomcat/conf/server.xml.bak-p7 2>/dev/null

    # Eliminar conector HTTPS anterior del script (idempotente)
    sed -i '/<!-- Conector HTTPS Practica 7/,/<\/Connector>/d' \
        /opt/tomcat/conf/server.xml 2>/dev/null || true

    sed -i "/<\/Service>/i\\
    <!-- Conector HTTPS Practica 7 -->\\
    <Connector port=\"${_ps}\" protocol=\"org.apache.coyote.http11.Http11NioProtocol\" maxThreads=\"150\" SSLEnabled=\"true\">\\
        <SSLHostConfig>\\
            <Certificate certificateKeystoreFile=\"conf/tomcat.p12\" certificateKeystorePassword=\"${_kspass}\" type=\"RSA\" />\\
        </SSLHostConfig>\\
    </Connector>" /opt/tomcat/conf/server.xml

    print_success "Conector HTTPS puerto ${_ps} agregado a server.xml"

    rc-service tomcat restart 2>/dev/null; sleep 10

    if rc-service tomcat status > /dev/null 2>&1; then
        print_success "✓ Tomcat activo"
        print_info "Espera ~15s para que arranque completamente"
    else
        print_warning "Tomcat no arrancó — revisa: tail -f /opt/tomcat/logs/catalina.out"
        return 1
    fi
}

# =============================================================================
# FUNCIÓN: Configurar FTPS en vsftpd
# =============================================================================
ssl_vsftpd() {
    print_title "VSFTPD — FTPS (FTP sobre TLS)"
    command -v vsftpd > /dev/null 2>&1 \
        || { print_warning "vsftpd no instalado"; return 1; }

    _conf="/etc/vsftpd/vsftpd.conf"
    [ -f "$_conf" ] || { print_warning "No existe $_conf"; return 1; }

    generar_cert "vsftpd" || return 1
    cp "$_conf" "${_conf}.bak-p7"

    for _k in ssl_enable rsa_cert_file rsa_private_key_file \
               ssl_tlsv1 ssl_sslv2 ssl_sslv3 \
               force_local_data_ssl force_local_logins_ssl require_ssl_reuse; do
        sed -i "/^${_k}/d" "$_conf"
    done

    cat >> "$_conf" << EOF

# ====== FTPS — Practica 7 ======
ssl_enable=YES
rsa_cert_file=${CERT_FILE}
rsa_private_key_file=${KEY_FILE}
ssl_tlsv1=YES
ssl_sslv2=NO
ssl_sslv3=NO
force_local_data_ssl=NO
force_local_logins_ssl=NO
require_ssl_reuse=NO
EOF

    rc-service vsftpd restart 2>/dev/null; sleep 2

    if rc-service vsftpd status > /dev/null 2>&1; then
        print_success "✓ vsftpd con FTPS activo en puerto 21"
        print_info "FileZilla: Protocolo = FTPS (TLS Explicito), Puerto 21"
    else
        print_warning "vsftpd no arrancó — revisa: tail -20 /var/log/vsftpd.log"
    fi
}

# =============================================================================
# FLUJO DE INSTALACIÓN
# =============================================================================
flujo_instalacion() {
    _svc="$1"

    print_title "INSTALAR $_svc"
    printf "${C_WHITE}  Fuente de instalacion:${C_RESET}\n\n"
    printf "  ${C_PINK}[W]${C_RESET} WEB — repositorios oficiales (apk)\n"
    printf "  ${C_PINK}[F]${C_RESET} FTP — repositorio privado (vsftpd local)\n\n"
    printf "${C_PINK}  Seleccione [W/F]: ${C_RESET}"
    read _fuente
    _fuente=$(echo "$_fuente" | tr 'a-z' 'A-Z')

    if [ "$_fuente" = "F" ]; then
        if cliente_ftp; then
            if [ "$_svc" = "Tomcat" ] && [ -n "$ARCHIVO_DESCARGADO" ]; then
                _ver=$(basename "$ARCHIVO_DESCARGADO" .tar.gz \
                       | sed 's/apache-tomcat-//')
                cp "$ARCHIVO_DESCARGADO" "/tmp/apache-tomcat-${_ver}.tar.gz"
                print_success "Tomcat v${_ver} preparado"
            fi
        else
            print_info "FTP fallo — instalando desde WEB..."
        fi
    fi

    # Instalar con funciones existentes de lib/http_functions.sh
    case "$_svc" in
        Apache) setup_apache ;;
        Nginx)  setup_nginx  ;;
        Tomcat) setup_tomcat ;;
    esac

    _puerto_http="${PUERTO_ELEGIDO:-80}"

    printf "\n${C_PINK}  ¿Activar SSL/TLS? [s/N]: ${C_RESET}"
    read _ssl
    _ssl=$(echo "$_ssl" | tr 'a-z' 'A-Z')

    if [ "$_ssl" = "S" ]; then
        pedir_puerto_https "$_puerto_http"

        case "$_svc" in
            Apache) ssl_apache "$_puerto_http" "$PUERTO_HTTPS" ;;
            Nginx)  ssl_nginx  "$_puerto_http" "$PUERTO_HTTPS" ;;
            Tomcat) ssl_tomcat "$_puerto_http" "$PUERTO_HTTPS" ;;
        esac
    fi

    # Resumen — la IP es solo informativa, no está en ninguna config
    _ip=$(obtener_ip_info)
    printf "\n"
    print_title "RESUMEN — $_svc"
    print_success "Servicio    : $_svc"
    print_success "Puerto HTTP : $_puerto_http"
    if [ "$_ssl" = "S" ]; then
        print_success "SSL/TLS     : Activo"
        print_info "HTTP        : http://${_ip}:${_puerto_http}"
        print_info "              (redirige automaticamente a HTTPS)"
        print_info "HTTPS       : https://${_ip}:${PUERTO_HTTPS}"
        print_info "Cert        : $SSL_DIR/certs/$(echo "$_svc" | tr 'A-Z' 'a-z').crt"
        print_info ""
        print_info "NOTA: Si la IP cambia solo reconecta — el servidor"
        print_info "      acepta cualquier IP sin necesidad de reinstalar"
    else
        print_info "HTTP        : http://${_ip}:${_puerto_http}"
    fi
}

# =============================================================================
# MENÚ PRINCIPAL
# =============================================================================
menu_principal() {
    while true; do
        clear
        print_title "PRACTICA 7 — ALPINE LINUX"
        printf "${C_PINK}1)${C_RESET} Instalar Apache2  (WEB o FTP + SSL opcional)\n"
        printf "${C_PINK}2)${C_RESET} Instalar Nginx    (WEB o FTP + SSL opcional)\n"
        printf "${C_PINK}3)${C_RESET} Instalar Tomcat   (WEB o FTP + SSL opcional)\n"
        printf "${C_PINK}4)${C_RESET} Activar FTPS en vsftpd\n"
        printf "${C_PINK}5)${C_RESET} Verificar servicios HTTP\n"
        printf "${C_PINK}6)${C_RESET} Revisar respuesta HTTP\n"
        printf "${C_PINK}0)${C_RESET} Salir\n\n"
        printf "${C_PINK}Seleccione [0-6]: ${C_RESET}"
        read OPCION

        case "$OPCION" in
            1) flujo_instalacion "Apache"  ;;
            2) flujo_instalacion "Nginx"   ;;
            3) flujo_instalacion "Tomcat"  ;;
            4) ssl_vsftpd ;;
            5) verificar_HTTP ;;
            6) revisar_HTTP   ;;
            0) print_info "Saliendo..."; exit 0 ;;
            *) print_warning "Opcion invalida" ;;
        esac

        pausar
    done
}

menu_principal