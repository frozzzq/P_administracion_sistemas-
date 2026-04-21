#!/bin/sh
# =============================================================================
# http_functions.sh — Funciones de instalacion de servidores HTTP
# Proyecto : Aprovisionamiento Web Automatizado
# SO       : Alpine Linux 3.23
# Uso      : source ./lib/http_functions.sh
# =============================================================================

# Asegurar que utilidades.sh está cargado
if [ -z "$C_RESET" ]; then
    echo "ERROR: Debes cargar utilidades.sh primero"
    exit 1
fi

# =============================================================================
# PALETA DE COLORES — Blanco, Amarillo y Azul
# =============================================================================
C_WHITE='\033[1;37m'
C_YELLOW='\033[1;33m'
C_BLUE='\033[1;34m'
C_RESET='\033[0m'

# =============================================================================
# APACHE2
# =============================================================================

consultar_versiones_apache() {
    print_info "Consultando versiones disponibles de Apache2..."
    apk update > /dev/null 2>&1
    version=$(apk info apache2 2>/dev/null | grep -oE 'apache2-[0-9]+\.[0-9]+\.[0-9]+' | sed 's/apache2-//g' | head -1)
    if [ -z "$version" ]; then
        version=$(apk search -x apache2 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    fi
    if [ -z "$version" ]; then
        print_warning "No se pudo consultar la version de Apache2"
        return 1
    fi
    printf "${C_BLUE}[OK]    Versión disponible: %s${C_RESET}\n" "$version"
    echo "$version"
    return 0
}

setup_apache() {
    print_title "INSTALACION DE APACHE2"
    VERSION_APACHE=$(consultar_versiones_apache)
    if [ $? -ne 0 ]; then
        print_warning "No se pudo obtener la versión de Apache2"
        return 1
    fi
    if ! pedir_puerto; then return 1; fi
    printf "\n${C_YELLOW}¿Instalar Apache2 v${VERSION_APACHE} en puerto ${PUERTO_ELEGIDO}? [s/N]: ${C_RESET}"
    read confirma
    if ! echo "$confirma" | grep -qiE '^s$'; then
        print_info "Instalacion cancelada."
        return 0
    fi
    print_info "Instalando Apache2..."
    apk add --no-cache apache2 apache2-utils > /dev/null 2>&1
    if [ $? -ne 0 ]; then print_warning "Error al instalar Apache2"; return 1; fi
    print_success "Apache2 instalado correctamente."
    crear_usuario_servicio "httpd-user" "/var/www/localhost/htdocs"
    if ! id -nG httpd-user 2>/dev/null | grep -q apache; then
        adduser httpd-user apache 2>/dev/null
    fi
    configurar_puerto_apache "$PUERTO_ELEGIDO"
    configurar_seguridad_apache
    crear_index "Apache2" "$VERSION_APACHE" "$PUERTO_ELEGIDO" "/var/www/localhost/htdocs"
    chown -R httpd-user:apache /var/www/localhost/htdocs
    chmod -R 755 /var/www/localhost/htdocs
    abrir_puerto_firewall "$PUERTO_ELEGIDO"
    rc-update add apache2 default 2>/dev/null
    rc-service apache2 restart
    sleep 2
    verificar_servicio "apache2" "$PUERTO_ELEGIDO"
    IP_SERVIDOR=$(ip addr show | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -d/ -f1 | head -1)
    print_title "APACHE2 INSTALADO EXITOSAMENTE"
    print_success "Version: $VERSION_APACHE"
    print_success "Puerto: $PUERTO_ELEGIDO"
    print_success "Usuario: httpd-user"
    print_info "Accede desde: http://${IP_SERVIDOR}:$PUERTO_ELEGIDO"
}

configurar_puerto_apache() {
    puerto="$1"
    conf="/etc/apache2/httpd.conf"
    print_info "Configurando puerto $puerto en Apache2..."

    # Eliminar TODAS las líneas Listen para evitar duplicados
    # (el httpd.conf de Alpine puede tener Listen 80 Y Listen 443)
    sed -i '/^Listen /d' "$conf"

    # Insertar UNA sola línea Listen después de ServerRoot
    sed -i "/^ServerRoot/a Listen $puerto" "$conf"

    if grep -q "^Listen $puerto" "$conf"; then
        print_success "Puerto configurado en $conf"
    else
        print_warning "Error al configurar puerto"
        return 1
    fi
    return 0
}

configurar_seguridad_apache() {
    conf="/etc/apache2/httpd.conf"
    print_info "Aplicando configuraciones de seguridad en Apache2..."
    if ! grep -q "ServerTokens Prod" "$conf"; then
        cat >> "$conf" << 'EOF'

# Security Hardening
ServerTokens Prod
ServerSignature Off
TraceEnable Off
EOF
        print_success "ServerTokens, ServerSignature y TraceEnable configurados"
    fi
    if ! grep -q "X-Frame-Options" "$conf"; then
        cat >> "$conf" << 'EOF'

# Security Headers
<IfModule mod_headers.c>
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
    Header always unset X-Powered-By
    Header always unset Server
</IfModule>
EOF
        print_success "Headers de seguridad configurados"
    fi
    # FIX: Solo modificar el Directory existente en lugar de agregar un bloque
    # duplicado que causa conflicto con el <Directory> ya definido en httpd.conf
    if ! grep -q "Options -Indexes" "$conf"; then
        sed -i 's/Options Indexes/Options -Indexes/' "$conf"
        print_success "Listado de directorios deshabilitado"
    fi
}

# =============================================================================
# NGINX
# =============================================================================

consultar_versiones_nginx() {
    print_info "Consultando versiones disponibles de Nginx..."
    apk update > /dev/null 2>&1
    version=$(apk info nginx 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [ -z "$version" ]; then
        version=$(apk search -x nginx 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    fi
    if [ -z "$version" ]; then print_warning "No se pudo consultar la versión de Nginx"; return 1; fi
    printf "${C_BLUE}[OK]    Versión disponible: %s${C_RESET}\n" "$version"
    echo "$version"
    return 0
}

setup_nginx() {
    print_title "INSTALACIÓN DE NGINX"
    VERSION_NGINX=$(consultar_versiones_nginx)
    if [ $? -ne 0 ]; then return 1; fi
    if ! pedir_puerto; then return 1; fi
    printf "\n${C_YELLOW}¿Instalar Nginx v${VERSION_NGINX} en puerto ${PUERTO_ELEGIDO}? [s/N]: ${C_RESET}"
    read confirma
    if ! echo "$confirma" | grep -qiE '^s$'; then print_info "Instalación cancelada."; return 0; fi
    print_info "Instalando Nginx..."
    apk add --no-cache nginx > /dev/null 2>&1
    if [ $? -ne 0 ]; then print_warning "Error al instalar Nginx"; return 1; fi
    print_success "Nginx instalado correctamente."
    mkdir -p /var/www/html /var/lib/nginx/tmp /run/nginx
    configurar_puerto_nginx "$PUERTO_ELEGIDO"
    configurar_seguridad_nginx
    crear_index "Nginx" "$VERSION_NGINX" "$PUERTO_ELEGIDO" "/var/www/html"
    chown -R nginx:nginx /var/www/html /var/lib/nginx /run/nginx
    chmod -R 755 /var/www/html
    abrir_puerto_firewall "$PUERTO_ELEGIDO"
    print_info "Verificando configuración de Nginx..."
    if nginx -t 2>&1 | grep -q "successful"; then
        print_success "Configuración de Nginx correcta"
    else
        print_warning "Revisa la configuración:"
        nginx -t
    fi
    rc-update add nginx default 2>/dev/null
    rc-service nginx restart
    sleep 3
    verificar_servicio "nginx" "$PUERTO_ELEGIDO"
    IP_SERVIDOR=$(ip addr show | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -d/ -f1 | head -1)
    print_title "NGINX INSTALADO EXITOSAMENTE"
    print_success "Versión: $VERSION_NGINX"
    print_success "Puerto: $PUERTO_ELEGIDO"
    print_info "Accede desde: http://${IP_SERVIDOR}:$PUERTO_ELEGIDO"
}

configurar_puerto_nginx() {
    puerto="$1"
    conf_dir="/etc/nginx/http.d"
    conf="$conf_dir/default.conf"
    print_info "Configurando puerto $puerto en Nginx..."
    mkdir -p "$conf_dir"
    cat > "$conf" << EOF
server {
    listen $puerto;
    server_name _;
    root /var/www/html;
    index index.html;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ /\\. {
        deny all;
    }
}
EOF
    print_success "Puerto configurado en $conf"
}

configurar_seguridad_nginx() {
    conf="/etc/nginx/nginx.conf"
    print_info "Aplicando configuraciones de seguridad en Nginx..."
    if ! grep -q "server_tokens off" "$conf"; then
        sed -i '/http {/a \    server_tokens off;' "$conf"
        print_success "server_tokens off configurado"
    fi
    if ! grep -q "^user nginx" "$conf"; then
        sed -i 's/^user .*/user nginx nginx;/' "$conf"
        print_success "Usuario nginx configurado"
    fi
}

# =============================================================================
# TOMCAT
# =============================================================================

setup_tomcat() {
    print_title "INSTALACIÓN DE TOMCAT"

    print_info "Versiones disponibles de Tomcat:"
    printf "${C_WHITE}  [1]${C_RESET} 10.1.20 (LTS - Recomendada)\n"
    printf "${C_WHITE}  [2]${C_RESET} 10.1.34 (Latest Stable)\n"
    printf "${C_WHITE}  [3]${C_RESET} 9.0.96  (Legacy LTS)\n"
    printf "${C_YELLOW}Selecciona versión [1-3]: ${C_RESET}"
    read ver_opcion

    case "$ver_opcion" in
        1) VERSION_TOMCAT="10.1.20" ;;
        2) VERSION_TOMCAT="10.1.34" ;;
        3) VERSION_TOMCAT="9.0.96" ;;
        *) print_warning "Opción inválida"; return 1 ;;
    esac
    print_success "Versión seleccionada: $VERSION_TOMCAT"

    if ! pedir_puerto; then return 1; fi

    printf "\n${C_YELLOW}¿Instalar Tomcat v${VERSION_TOMCAT} en puerto ${PUERTO_ELEGIDO}? [s/N]: ${C_RESET}"
    read confirma
    if ! echo "$confirma" | grep -qiE '^s$'; then print_info "Instalación cancelada."; return 0; fi

    # =========================================================
    # LIMPIEZA COMPLETA de instancia anterior:
    # 1. Apagado limpio via rc-service
    # 2. Matar proceso con pkill -9 si sigue vivo
    # 3. Actualizar puerto en server.xml si ya existe
    # Se ejecuta SIEMPRE para garantizar limpieza total
    # =========================================================
    print_info "Limpiando instancia anterior de Tomcat..."
    rc-service tomcat stop 2>/dev/null
    sleep 2

    # Forzar cierre si el proceso Java sigue vivo
    if pgrep -f "catalina" > /dev/null 2>&1; then
        print_info "Proceso Tomcat sigue vivo, forzando cierre..."
        pkill -9 -f "catalina" 2>/dev/null
        sleep 2
    fi

    # Verificar que realmente terminó
    if pgrep -f "catalina" > /dev/null 2>&1; then
        print_warning "No se pudo detener Tomcat. Reinicia el servidor e intenta de nuevo."
        return 1
    fi

    # Si server.xml ya existe, actualizar el puerto directamente
    if [ -f "/opt/tomcat/conf/server.xml" ]; then
        sed -i "s/\(<Connector[^>]*\)port=\"[0-9]*\"/\1port=\"$PUERTO_ELEGIDO\"/" /opt/tomcat/conf/server.xml
        echo "$PUERTO_ELEGIDO" > /opt/tomcat/conf/tomcat_port
        print_info "Puerto actualizado en server.xml existente."
    fi

    print_success "Limpieza completada."

    print_info "Instalando OpenJDK 17..."
    apk add --no-cache openjdk17 wget ca-certificates > /dev/null 2>&1
    print_success "OpenJDK 17 instalado"

    # =========================================================
    # FIX PUERTOS PRIVILEGIADOS (< 1024):
    # sysctl net.ipv4.ip_unprivileged_port_start=<puerto>
    # Método recomendado en Alpine Linux.
    # =========================================================
    if [ "$PUERTO_ELEGIDO" -lt 1024 ]; then
        print_info "Puerto $PUERTO_ELEGIDO < 1024: configurando kernel para permitir bind..."
        sysctl -w net.ipv4.ip_unprivileged_port_start="$PUERTO_ELEGIDO" > /dev/null 2>&1
        if ! grep -q "ip_unprivileged_port_start" /etc/sysctl.conf 2>/dev/null; then
            echo "net.ipv4.ip_unprivileged_port_start=$PUERTO_ELEGIDO" >> /etc/sysctl.conf
        else
            sed -i "s/net.ipv4.ip_unprivileged_port_start=.*/net.ipv4.ip_unprivileged_port_start=$PUERTO_ELEGIDO/" /etc/sysctl.conf
        fi
        actual=$(sysctl -n net.ipv4.ip_unprivileged_port_start 2>/dev/null)
        if [ "$actual" -le "$PUERTO_ELEGIDO" ]; then
            print_success "Kernel: puertos >= $PUERTO_ELEGIDO permitidos para usuarios no-root."
        else
            print_warning "No se pudo aplicar sysctl. Verifica permisos del kernel."
            return 1
        fi
    fi

    if ! id tomcat > /dev/null 2>&1; then
        adduser -D -h /opt/tomcat -s /sbin/nologin tomcat 2>/dev/null
        print_success "Usuario 'tomcat' creado"
    fi

    print_info "Descargando Tomcat $VERSION_TOMCAT..."
    TOMCAT_MAJOR="${VERSION_TOMCAT%%.*}"
    cd /tmp || return 1
    descarga_exitosa=0

    for mirror in \
        "https://dlcdn.apache.org/tomcat/tomcat-${TOMCAT_MAJOR}/v${VERSION_TOMCAT}/bin/apache-tomcat-${VERSION_TOMCAT}.tar.gz" \
        "https://archive.apache.org/dist/tomcat/tomcat-${TOMCAT_MAJOR}/v${VERSION_TOMCAT}/bin/apache-tomcat-${VERSION_TOMCAT}.tar.gz" \
        "https://downloads.apache.org/tomcat/tomcat-${TOMCAT_MAJOR}/v${VERSION_TOMCAT}/bin/apache-tomcat-${VERSION_TOMCAT}.tar.gz"
    do
        print_info "Intentando: $mirror"
        rm -f tomcat.tar.gz
        if wget -q --show-progress "$mirror" -O tomcat.tar.gz 2>&1 && \
           [ -f tomcat.tar.gz ] && [ -s tomcat.tar.gz ]; then
            descarga_exitosa=1
            print_success "Tomcat descargado exitosamente"
            break
        fi
    done

    if [ "$descarga_exitosa" -eq 0 ]; then
        rm -f tomcat.tar.gz
        print_warning "No se pudo descargar Tomcat de ningún mirror."
        return 1
    fi

    print_info "Extrayendo Tomcat..."
    rm -rf /opt/tomcat
    mkdir -p /opt/tomcat
    if ! tar -xzf tomcat.tar.gz -C /opt/tomcat --strip-components=1 2>/dev/null; then
        print_warning "Error al extraer Tomcat."
        rm -f tomcat.tar.gz
        return 1
    fi
    rm -f tomcat.tar.gz
    print_success "Tomcat extraído en /opt/tomcat"

    chown -R tomcat:tomcat /opt/tomcat
    chmod -R 750 /opt/tomcat
    chmod +x /opt/tomcat/bin/*.sh

    configurar_puerto_tomcat "$PUERTO_ELEGIDO"
    configurar_seguridad_tomcat
    crear_index_tomcat "$VERSION_TOMCAT" "$PUERTO_ELEGIDO"
    abrir_puerto_firewall "$PUERTO_ELEGIDO"
    crear_servicio_tomcat "$PUERTO_ELEGIDO"

    print_info "Esperando a que Tomcat inicie (10 segundos)..."
    sleep 10
    verificar_servicio "tomcat" "$PUERTO_ELEGIDO"

    IP_SERVIDOR=$(ip addr show | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -d/ -f1 | head -1)
    print_title "TOMCAT INSTALADO EXITOSAMENTE"
    print_success "Version: $VERSION_TOMCAT"
    print_success "Puerto: $PUERTO_ELEGIDO"
    print_info "Accede desde: http://${IP_SERVIDOR}:$PUERTO_ELEGIDO"
    print_info "Logs: tail -f /opt/tomcat/logs/catalina.out"
}

# -----------------------------------------------------------------------------
# FIX PRINCIPAL: configurar_puerto_tomcat
# Reemplaza CUALQUIER puerto existente en el Connector HTTP
# -----------------------------------------------------------------------------
configurar_puerto_tomcat() {
    puerto="$1"
    conf="/opt/tomcat/conf/server.xml"
    print_info "Configurando puerto $puerto en Tomcat..."

    sed -i "s/\(<Connector[^>]*\)port=\"[0-9]*\"/\1port=\"$puerto\"/" "$conf"

    if grep -q "port=\"$puerto\"" "$conf"; then
        print_success "Puerto $puerto configurado en $conf"
    else
        print_warning "No se pudo verificar el puerto en $conf"
        print_info "Verifica manualmente: grep 'port=' $conf"
        return 1
    fi

    return 0
}

configurar_seguridad_tomcat() {
    print_info "Aplicando configuraciones de seguridad en Tomcat..."
    conf="/opt/tomcat/conf/server.xml"
    if ! grep -q 'server=""' "$conf"; then
        sed -i 's/<Connector port/<Connector server="" port/g' "$conf"
        print_success "Versión del servidor ocultada"
    fi
}

crear_index_tomcat() {
    version="$1"
    puerto="$2"
    webapps="/opt/tomcat/webapps/ROOT"
    rm -rf "$webapps"/*
    cat > "$webapps/index.jsp" << EOF
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Servidor Web</title>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: 'Segoe UI', system-ui, sans-serif;
      background: #0d1117; color: #e6edf3;
      min-height: 100vh; display: flex;
      align-items: center; justify-content: center;
    }
    .card {
      border: 1px solid #1f3a5f; border-radius: 12px;
      padding: 2.5rem 3.5rem; text-align: center;
      background: #0d1f35; min-width: 320px;
    }
    .badge {
      display: inline-block; background: #f0c040; color: #0d1117;
      font-size: 0.7rem; font-weight: 700; letter-spacing: 0.12em;
      text-transform: uppercase; padding: 0.25rem 0.75rem;
      border-radius: 20px; margin-bottom: 1.25rem;
    }
    h1 { font-size: 1.5rem; font-weight: 600; color: #ffffff; margin-bottom: 1.75rem; }
    .info { display: flex; flex-direction: column; gap: 0.6rem; }
    .row {
      display: flex; justify-content: space-between; align-items: center;
      padding: 0.5rem 0.75rem; border-radius: 6px;
      background: #112240; font-size: 0.9rem;
    }
    .label { color: #8b9ab0; }
    .value { color: #f0c040; font-weight: 600; }
    .divider { border: none; border-top: 1px solid #1f3a5f; margin: 1.5rem 0; }
    .status { font-size: 0.8rem; color: #4a9eff; letter-spacing: 0.05em; }
  </style>
</head>
<body>
  <div class="card">
    <span class="badge">en línea</span>
    <h1>Apache Tomcat</h1>
    <div class="info">
      <div class="row"><span class="label">Versión</span><span class="value">$version</span></div>
      <div class="row"><span class="label">Puerto</span><span class="value">$puerto</span></div>
      <div class="row"><span class="label">Sistema</span><span class="value">Alpine Linux 3.23</span></div>
    </div>
    <hr class="divider">
    <p class="status">Servidor HTTP activo</p>
  </div>
</body>
</html>
EOF
    chown -R tomcat:tomcat "$webapps"
    print_success "index.jsp creado"
}

crear_servicio_tomcat() {
    puerto="$1"
    service="/etc/init.d/tomcat"

    echo "$puerto" > /opt/tomcat/conf/tomcat_port
    chown tomcat:tomcat /opt/tomcat/conf/tomcat_port

    cat > "$service" << INITEOF
#!/sbin/openrc-run

description="Apache Tomcat Server"

export JAVA_HOME=/usr/lib/jvm/default-jvm
export CATALINA_HOME=/opt/tomcat
export CATALINA_PID=/opt/tomcat/temp/tomcat.pid

depend() {
    need net
}

start() {
    ebegin "Starting Tomcat"
    puerto_conf=\$(cat /opt/tomcat/conf/tomcat_port 2>/dev/null)
    if [ -n "\$puerto_conf" ] && [ "\$puerto_conf" -lt 1024 ]; then
        sysctl -w net.ipv4.ip_unprivileged_port_start="\$puerto_conf" > /dev/null 2>&1
    fi
    su -s /bin/sh tomcat -c "\$CATALINA_HOME/bin/startup.sh"
    eend \$?
}

stop() {
    ebegin "Stopping Tomcat"
    su -s /bin/sh tomcat -c "\$CATALINA_HOME/bin/shutdown.sh"
    sleep 3
    pkill -f "catalina" 2>/dev/null
    eend 0
}
INITEOF

    chmod +x "$service"
    rc-update add tomcat default 2>/dev/null
    rc-service tomcat start
    print_success "Servicio Tomcat creado e iniciado"
}

# =============================================================================
# SSL — APACHE
# =============================================================================
# FIX: El paquete apache2-ssl crea /etc/apache2/conf.d/ssl.conf que:
#   1. Agrega su propio "Listen 443" → conflicto si el usuario eligió otro puerto
#   2. Referencia certificados en /etc/ssl/apache2/ que NO existen → Apache crashea
# Solución: deshabilitar ssl.conf del paquete antes de aplicar nuestra config.
# =============================================================================
ssl_apache() {
    _ph="$1"   # puerto HTTP
    _ps="$2"   # puerto HTTPS

    print_title "APACHE — SSL/TLS (HTTP:${_ph} → HTTPS:${_ps})"

    apk info -e apache2-ssl > /dev/null 2>&1 \
        || apk add --no-cache apache2-ssl > /dev/null 2>&1

    # FIX: Deshabilitar ssl.conf del paquete — referencia certs inexistentes
    # y genera conflictos de Listen/VirtualHost con nuestra configuración
    if [ -f /etc/apache2/conf.d/ssl.conf ]; then
        mv /etc/apache2/conf.d/ssl.conf \
           /etc/apache2/conf.d/ssl.conf.disabled 2>/dev/null
        print_info "ssl.conf del paquete deshabilitado (evita conflicto de certs)"
    fi

    generar_cert "apache" || return 1

    # Limpiar directivas que versiones anteriores del script pudieron dejar
    sed -i '/LoadModule ssl_module/d'     /etc/apache2/httpd.conf
    sed -i '/LoadModule rewrite_module/d' /etc/apache2/httpd.conf
    sed -i '/LoadModule headers_module/d' /etc/apache2/httpd.conf
    # Eliminar cualquier Listen del puerto HTTPS que ya exista en httpd.conf
    sed -i "/^Listen ${_ps}$/d"           /etc/apache2/httpd.conf

    _docroot=$(grep "^DocumentRoot" /etc/apache2/httpd.conf 2>/dev/null \
               | head -1 | awk '{print $2}' | tr -d '"')
    _docroot="${_docroot:-/var/www/localhost/htdocs}"

    # %{HTTP_HOST} captura la IP real de la petición — sin hardcodear nada
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

    # Verificar sintaxis antes de reiniciar
    if ! httpd -t 2>/dev/null; then
        print_warning "Error de sintaxis en la configuración de Apache:"
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
# SSL — NGINX
# =============================================================================
ssl_nginx() {
    _ph="$1"
    _ps="$2"

    print_title "NGINX — SSL/TLS (HTTP:${_ph} → HTTPS:${_ps})"

    generar_cert "nginx" || return 1
    iptables -A INPUT -p tcp --dport "$_ps" -j ACCEPT 2>/dev/null || true

    # $host captura la IP real de la petición — sin hardcodear nada
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
# SSL — TOMCAT
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
# SSL — VSFTPD (FTPS)
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
# VERIFICACIÓN Y REVISIÓN
# =============================================================================

verificar_HTTP() {
    print_title "ESTADO DE SERVICIOS HTTP"
    if rc-service apache2 status > /dev/null 2>&1; then
        puerto=$(grep "^Listen" /etc/apache2/httpd.conf 2>/dev/null | awk '{print $2}' | head -1)
        printf "${C_BLUE}✓ Apache2${C_RESET}  →  Running en puerto ${C_YELLOW}%s${C_RESET}\n" "$puerto"
    else
        printf "${C_WHITE}✗ Apache2${C_RESET}  →  Detenido\n"
    fi
    if rc-service nginx status > /dev/null 2>&1; then
        puerto=$(grep "listen" /etc/nginx/http.d/default.conf 2>/dev/null | grep -oE '[0-9]+' | head -1)
        printf "${C_BLUE}✓ Nginx${C_RESET}     →  Running en puerto ${C_YELLOW}%s${C_RESET}\n" "$puerto"
    else
        printf "${C_WHITE}✗ Nginx${C_RESET}     →  Detenido\n"
    fi
    if rc-service tomcat status > /dev/null 2>&1; then
        puerto=$(grep 'Connector.*port=' /opt/tomcat/conf/server.xml 2>/dev/null | grep -oE 'port="[0-9]+"' | head -1 | grep -oE '[0-9]+')
        printf "${C_BLUE}✓ Tomcat${C_RESET}    →  Running en puerto ${C_YELLOW}%s${C_RESET}\n" "$puerto"
    else
        printf "${C_WHITE}✗ Tomcat${C_RESET}    →  Detenido\n"
    fi
    printf "\n${C_WHITE}Puertos en escucha:${C_RESET}\n"
    netstat -tuln 2>/dev/null | grep LISTEN || ss -tuln 2>/dev/null | grep LISTEN
}

revisar_HTTP() {
    print_title "REVISAR RESPUESTA HTTP"
    printf "${C_YELLOW}Ingresa el puerto a verificar: ${C_RESET}"
    read puerto
    if ! validar_puerto "$puerto"; then
        print_warning "Puerto invalido o no en uso"
        return 1
    fi
    print_info "Probando http://localhost:$puerto ..."
    printf "\n${C_WHITE}━━━ HEADERS HTTP ━━━${C_RESET}\n"
    curl -I "http://localhost:$puerto" 2>/dev/null
    printf "${C_WHITE}━━━━━━━━━━━━━━━━━━━━${C_RESET}\n\n"
    print_info "Probando conectividad..."
    if curl -s "http://localhost:$puerto" > /dev/null 2>&1; then
        print_success "Servidor respondiendo correctamente"
    else
        print_warning "El servidor no responde o hay un error"
    fi
}

verificar_servicio() {
    servicio="$1"
    puerto="$2"
    print_info "Verificando servicio $servicio en puerto $puerto..."
    sleep 2
    if netstat -tuln 2>/dev/null | grep -q ":${puerto} " || ss -tuln 2>/dev/null | grep -q ":${puerto} "; then
        print_success "Servicio escuchando en puerto $puerto"
    else
        print_warning "Servicio NO escuchando en puerto $puerto"
        print_info "Revisa logs: tail -f /opt/tomcat/logs/catalina.out"
        return 1
    fi
    if command -v curl > /dev/null 2>&1; then
        response=$(curl -I "http://localhost:$puerto" 2>/dev/null | head -1)
        if echo "$response" | grep -qE "200|301|302"; then
            print_success "Respuesta HTTP: $response"
        else
            print_warning "Respuesta HTTP inesperada: $response"
        fi
    fi
}