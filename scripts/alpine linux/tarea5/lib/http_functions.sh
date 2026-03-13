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
    sed -i "s/^Listen .*/Listen $puerto/g" "$conf"
    if grep -q "Listen $puerto" "$conf"; then
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
    if ! grep -q "Options -Indexes" "$conf"; then
        cat >> "$conf" << 'EOF'

# Disable directory listing
<Directory /var/www/localhost/htdocs>
    Options -Indexes +FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>
EOF
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
    # Evita que arranque en el puerto anterior si se reutiliza /opt/tomcat
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
    # En Linux, por defecto solo root puede abrir puertos < 1024.
    # Solución: bajar el límite del kernel con sysctl.
    #
    # Por qué NO usamos setcap en Alpine+OpenJDK:
    #   setcap no funciona sobre symlinks. OpenJDK en Alpine
    #   instala java como symlink, y al aplicar setcap al binario
    #   real rompe la carga de libjli.so (shared library),
    #   dejando Java completamente inutilizable.
    #
    # sysctl net.ipv4.ip_unprivileged_port_start=<puerto>
    #   Le dice al kernel que desde ese número en adelante,
    #   cualquier usuario (no solo root) puede hacer bind.
    #   Es el método recomendado en Alpine Linux.
    # =========================================================
    if [ "$PUERTO_ELEGIDO" -lt 1024 ]; then
        print_info "Puerto $PUERTO_ELEGIDO < 1024: configurando kernel para permitir bind..."
        # Aplicar en caliente (esta sesión)
        sysctl -w net.ipv4.ip_unprivileged_port_start="$PUERTO_ELEGIDO" > /dev/null 2>&1
        # Persistir en reinicios
        if ! grep -q "ip_unprivileged_port_start" /etc/sysctl.conf 2>/dev/null; then
            echo "net.ipv4.ip_unprivileged_port_start=$PUERTO_ELEGIDO" >> /etc/sysctl.conf
        else
            sed -i "s/net.ipv4.ip_unprivileged_port_start=.*/net.ipv4.ip_unprivileged_port_start=$PUERTO_ELEGIDO/" /etc/sysctl.conf
        fi
        # Verificar que se aplicó
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
# Problema original: sed solo buscaba port="8080"
# Si Tomcat ya estaba instalado con otro puerto (ej. 8000), el sed
# no encontraba nada y server.xml quedaba sin cambios.
# Solucion: reemplazar CUALQUIER puerto existente en el Connector HTTP
# -----------------------------------------------------------------------------
configurar_puerto_tomcat() {
    puerto="$1"
    conf="/opt/tomcat/conf/server.xml"
    print_info "Configurando puerto $puerto en Tomcat..."

    # Reemplaza el puerto en el Connector HTTP (cualquier valor actual)
    # Busca: port="CUALQUIER_NUMERO" dentro de la linea del Connector HTTP
    sed -i "s/\(<Connector[^>]*\)port=\"[0-9]*\"/\1port=\"$puerto\"/" "$conf"

    # Verificar que el cambio se aplicó
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

    # Guardar el puerto para que el init script lo lea en reinicios
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
    # Aplicar sysctl si el puerto es privilegiado (necesario en cada reinicio)
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