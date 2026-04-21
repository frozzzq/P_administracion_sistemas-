#!/bin/sh
# =============================================================================
# p7_orquestador.sh — Orquestador de instalacion hibrida (WEB / FTP)
# Navegacion dinamica del repositorio FTP, verificacion de integridad SHA256
# SO: Alpine Linux 3.23
# =============================================================================

FTP_REPO_BASE="/srv/ftp/pub/http"
FTP_USER="anonymous"
FTP_PASS=""
FTP_IP=""

# =============================================================================
# PREPARAR REPOSITORIO FTP
# Descarga paquetes reales y los coloca en la estructura del servidor FTP
# =============================================================================
preparar_repo_ftp() {
    print_title "PREPARAR REPOSITORIO FTP"

    # Verificar que vsftpd esta instalado
    if ! command -v vsftpd > /dev/null 2>&1; then
        print_warning "vsftpd no esta instalado. Ejecuta primero el script de la Practica 5."
        return 1
    fi

    print_info "Creando estructura del repositorio..."
    for dir in "$FTP_REPO_BASE/Linux/Apache" "$FTP_REPO_BASE/Linux/Nginx" "$FTP_REPO_BASE/Linux/Tomcat" \
               "$FTP_REPO_BASE/Windows/Apache" "$FTP_REPO_BASE/Windows/Nginx" "$FTP_REPO_BASE/Windows/IIS"; do
        mkdir -p "$dir"
    done
    print_success "Estructura de directorios creada."

    # Actualizar indices de paquetes
    print_info "Actualizando repositorios de Alpine..."
    apk update > /dev/null 2>&1

    # ---- Apache ----
    print_info "Descargando paquete Apache2..."
    cd "$FTP_REPO_BASE/Linux/Apache" || return 1
    apk fetch apache2 2>/dev/null
    apk fetch apache2-utils 2>/dev/null
    apk fetch apache2-ssl 2>/dev/null
    for f in *.apk; do
        [ -f "$f" ] || continue
        sha256sum "$f" > "${f}.sha256"
        print_success "  $f + hash SHA256"
    done

    # ---- Nginx ----
    print_info "Descargando paquete Nginx..."
    cd "$FTP_REPO_BASE/Linux/Nginx" || return 1
    apk fetch nginx 2>/dev/null
    for f in *.apk; do
        [ -f "$f" ] || continue
        sha256sum "$f" > "${f}.sha256"
        print_success "  $f + hash SHA256"
    done

    # ---- Tomcat ----
    print_info "Descargando Tomcat (tar.gz)..."
    cd "$FTP_REPO_BASE/Linux/Tomcat" || return 1

    # Intentar descargar multiples versiones
    for ver in "10.1.20" "10.1.34" "9.0.96"; do
        major="${ver%%.*}"
        archivo="apache-tomcat-${ver}.tar.gz"
        [ -f "$archivo" ] && { print_info "  $archivo ya existe, omitiendo."; continue; }
        descargado=0
        for mirror in \
            "https://dlcdn.apache.org/tomcat/tomcat-${major}/v${ver}/bin/${archivo}" \
            "https://archive.apache.org/dist/tomcat/tomcat-${major}/v${ver}/bin/${archivo}"; do
            if wget -q "$mirror" -O "$archivo" 2>/dev/null && [ -s "$archivo" ]; then
                descargado=1
                break
            fi
            rm -f "$archivo"
        done
        if [ "$descargado" -eq 1 ]; then
            sha256sum "$archivo" > "${archivo}.sha256"
            print_success "  $archivo + hash SHA256"
        else
            print_warning "  No se pudo descargar Tomcat $ver (mirror no disponible)"
        fi
    done

    # Permisos para anonymous FTP
    chown -R root:ftp "$FTP_REPO_BASE"
    chmod -R 755 "$FTP_REPO_BASE"

    print_title "REPOSITORIO FTP LISTO"
    print_info "Estructura:"
    find "$FTP_REPO_BASE" -type f -name "*.apk" -o -name "*.tar.gz" | while read f; do
        printf "  ${C_ROSE}%s${C_RESET}\n" "$f"
    done
    print_info "Ubicacion: $FTP_REPO_BASE"
}

# =============================================================================
# VERIFICAR HASH SHA256
# =============================================================================
verificar_hash_sha256() {
    archivo="$1"
    archivo_hash="$2"

    if [ ! -f "$archivo" ]; then
        print_warning "Archivo no encontrado: $archivo"
        return 1
    fi
    if [ ! -f "$archivo_hash" ]; then
        print_warning "Archivo hash no encontrado: $archivo_hash"
        return 1
    fi

    hash_esperado=$(awk '{print $1}' "$archivo_hash")
    hash_calculado=$(sha256sum "$archivo" | awk '{print $1}')

    print_info "Hash esperado : $hash_esperado"
    print_info "Hash calculado: $hash_calculado"

    if [ "$hash_esperado" = "$hash_calculado" ]; then
        print_success "Integridad verificada: hashes coinciden."
        return 0
    else
        print_warning "INTEGRIDAD FALLIDA: los hashes NO coinciden."
        print_warning "El archivo puede estar corrupto. Abortando instalacion."
        return 1
    fi
}

# =============================================================================
# PEDIR IP DEL SERVIDOR FTP
# =============================================================================
pedir_ip_ftp() {
    IP_AUTO=$(obtener_ip)
    printf "${C_PINK}IP del servidor FTP (Enter = $IP_AUTO): ${C_RESET}"
    read ip_input
    [ -z "$ip_input" ] && ip_input="$IP_AUTO"
    FTP_IP="$ip_input"
    export FTP_IP

    # Probar conectividad
    print_info "Probando conexion a ftp://$FTP_IP ..."
    if curl -s --connect-timeout 5 "ftp://$FTP_IP/" > /dev/null 2>&1; then
        print_success "Conexion FTP exitosa."
        return 0
    else
        print_warning "No se pudo conectar a ftp://$FTP_IP"
        return 1
    fi
}

# =============================================================================
# NAVEGAR REPOSITORIO FTP DINAMICAMENTE
# Retorna: nombre del archivo elegido en ARCHIVO_FTP_ELEGIDO
#          ruta completa FTP en RUTA_FTP_COMPLETA
# =============================================================================
navegar_ftp() {
    if [ -z "$FTP_IP" ]; then
        if ! pedir_ip_ftp; then return 1; fi
    fi

    print_title "NAVEGACION DEL REPOSITORIO FTP"
    BASE_URL="ftp://$FTP_IP/http"

    # Paso 1: Listar sistemas operativos
    print_info "Conectando a $BASE_URL ..."
    lista_os=$(curl -s --list-only "$BASE_URL/" 2>/dev/null)
    if [ -z "$lista_os" ]; then
        print_warning "No se encontro el repositorio en $BASE_URL"
        print_info "Ejecuta primero: Opcion 1 (Preparar repositorio FTP)"
        return 1
    fi

    printf "\n${C_ROSE}  Sistemas operativos disponibles:${C_RESET}\n"
    i=1
    echo "$lista_os" | while read linea; do
        printf "    ${C_WHITE}[%d]${C_RESET} %s\n" "$i" "$linea"
        i=$((i + 1))
    done

    # Auto-seleccionar Linux
    print_info "Sistema detectado: Linux (auto-seleccionado)"
    OS_ELEGIDO="Linux"

    # Paso 2: Listar servicios
    print_info "Listando servicios en $BASE_URL/$OS_ELEGIDO/ ..."
    lista_servicios=$(curl -s --list-only "$BASE_URL/$OS_ELEGIDO/" 2>/dev/null)
    if [ -z "$lista_servicios" ]; then
        print_warning "No hay servicios en el repositorio para Linux."
        return 1
    fi

    printf "\n${C_ROSE}  Servicios disponibles:${C_RESET}\n"
    i=1
    # Guardar en archivo temporal para indexar
    echo "$lista_servicios" > /tmp/p7_servicios.tmp
    while read linea; do
        printf "    ${C_WHITE}[%d]${C_RESET} %s\n" "$i" "$linea"
        i=$((i + 1))
    done < /tmp/p7_servicios.tmp

    total_svc=$(wc -l < /tmp/p7_servicios.tmp)
    printf "\n${C_PINK}Selecciona servicio [1-$total_svc]: ${C_RESET}"
    read sel_svc
    if ! echo "$sel_svc" | grep -qE '^[0-9]+$' || [ "$sel_svc" -lt 1 ] || [ "$sel_svc" -gt "$total_svc" ]; then
        print_warning "Seleccion invalida."
        return 1
    fi
    SERVICIO_ELEGIDO=$(sed -n "${sel_svc}p" /tmp/p7_servicios.tmp)
    print_success "Servicio seleccionado: $SERVICIO_ELEGIDO"

    # Paso 3: Listar archivos (excluyendo .sha256)
    print_info "Listando archivos en $BASE_URL/$OS_ELEGIDO/$SERVICIO_ELEGIDO/ ..."
    lista_archivos=$(curl -s --list-only "$BASE_URL/$OS_ELEGIDO/$SERVICIO_ELEGIDO/" 2>/dev/null | grep -v '\.sha256$')
    if [ -z "$lista_archivos" ]; then
        print_warning "No hay archivos en el repositorio para $SERVICIO_ELEGIDO."
        return 1
    fi

    printf "\n${C_ROSE}  Archivos disponibles:${C_RESET}\n"
    i=1
    echo "$lista_archivos" > /tmp/p7_archivos.tmp
    while read linea; do
        printf "    ${C_WHITE}[%d]${C_RESET} %s\n" "$i" "$linea"
        i=$((i + 1))
    done < /tmp/p7_archivos.tmp

    total_arch=$(wc -l < /tmp/p7_archivos.tmp)
    printf "\n${C_PINK}Selecciona archivo [1-$total_arch]: ${C_RESET}"
    read sel_arch
    if ! echo "$sel_arch" | grep -qE '^[0-9]+$' || [ "$sel_arch" -lt 1 ] || [ "$sel_arch" -gt "$total_arch" ]; then
        print_warning "Seleccion invalida."
        return 1
    fi
    ARCHIVO_FTP_ELEGIDO=$(sed -n "${sel_arch}p" /tmp/p7_archivos.tmp)
    RUTA_FTP_COMPLETA="$BASE_URL/$OS_ELEGIDO/$SERVICIO_ELEGIDO/$ARCHIVO_FTP_ELEGIDO"
    export ARCHIVO_FTP_ELEGIDO RUTA_FTP_COMPLETA SERVICIO_ELEGIDO

    print_success "Archivo seleccionado: $ARCHIVO_FTP_ELEGIDO"
    print_info "URL: $RUTA_FTP_COMPLETA"
    rm -f /tmp/p7_servicios.tmp /tmp/p7_archivos.tmp
    return 0
}

# =============================================================================
# DESCARGAR DESDE FTP + VERIFICAR HASH
# =============================================================================
descargar_desde_ftp() {
    if [ -z "$RUTA_FTP_COMPLETA" ]; then
        print_warning "No hay archivo seleccionado para descargar."
        return 1
    fi

    destino="/tmp/$ARCHIVO_FTP_ELEGIDO"
    destino_hash="/tmp/${ARCHIVO_FTP_ELEGIDO}.sha256"

    # Descargar archivo principal
    print_info "Descargando $ARCHIVO_FTP_ELEGIDO ..."
    if ! curl -s -o "$destino" "$RUTA_FTP_COMPLETA"; then
        print_warning "Error al descargar $ARCHIVO_FTP_ELEGIDO"
        return 1
    fi
    if [ ! -s "$destino" ]; then
        print_warning "Archivo descargado esta vacio."
        rm -f "$destino"
        return 1
    fi
    print_success "Archivo descargado: $destino"

    # Descargar hash
    print_info "Descargando hash SHA256..."
    if curl -s -o "$destino_hash" "${RUTA_FTP_COMPLETA}.sha256" 2>/dev/null && [ -s "$destino_hash" ]; then
        print_success "Hash descargado: $destino_hash"
        # Verificar integridad
        if ! verificar_hash_sha256 "$destino" "$destino_hash"; then
            rm -f "$destino" "$destino_hash"
            return 1
        fi
    else
        print_warning "No se encontro archivo .sha256 en el servidor."
        printf "${C_PINK}Continuar sin verificacion de integridad? [s/N]: ${C_RESET}"
        read continuar
        if ! echo "$continuar" | grep -qiE '^s$'; then
            rm -f "$destino" "$destino_hash"
            return 1
        fi
    fi

    ARCHIVO_DESCARGADO="$destino"
    export ARCHIVO_DESCARGADO
    return 0
}

# =============================================================================
# INSTALADORES LOCALES (desde archivo descargado por FTP)
# =============================================================================
instalar_apache_local() {
    archivo="$1"
    print_info "Instalando Apache2 desde archivo local..."
    # Instalar dependencias desde repos oficiales
    apk add --no-cache apr apr-util pcre2 > /dev/null 2>&1
    # Instalar el paquete local
    apk add --allow-untrusted "$archivo" > /dev/null 2>&1
    if ! command -v httpd > /dev/null 2>&1 && ! command -v apache2 > /dev/null 2>&1; then
        # Fallback: si el .apk no instalo bien, instalar todos los .apk descargados
        for f in /tmp/apache2*.apk; do
            [ -f "$f" ] && apk add --allow-untrusted "$f" > /dev/null 2>&1
        done
    fi
    apk add --no-cache apache2-utils > /dev/null 2>&1
    print_success "Apache2 instalado desde repositorio FTP."
}

instalar_nginx_local() {
    archivo="$1"
    print_info "Instalando Nginx desde archivo local..."
    apk add --no-cache pcre2 > /dev/null 2>&1
    apk add --allow-untrusted "$archivo" > /dev/null 2>&1
    print_success "Nginx instalado desde repositorio FTP."
}

instalar_tomcat_local() {
    archivo="$1"
    print_info "Instalando Tomcat desde archivo local..."
    apk add --no-cache openjdk17 > /dev/null 2>&1
    # Detener instancia anterior
    rc-service tomcat stop 2>/dev/null
    sleep 2
    if pgrep -f "catalina" > /dev/null 2>&1; then
        pkill -9 -f "catalina" 2>/dev/null; sleep 2
    fi
    # Crear usuario
    if ! id tomcat > /dev/null 2>&1; then
        adduser -D -h /opt/tomcat -s /sbin/nologin tomcat 2>/dev/null
    fi
    # Extraer
    rm -rf /opt/tomcat
    mkdir -p /opt/tomcat
    if ! tar -xzf "$archivo" -C /opt/tomcat --strip-components=1 2>/dev/null; then
        print_warning "Error al extraer Tomcat."
        return 1
    fi
    chown -R tomcat:tomcat /opt/tomcat
    chmod -R 750 /opt/tomcat
    chmod +x /opt/tomcat/bin/*.sh
    print_success "Tomcat extraido en /opt/tomcat desde repositorio FTP."
}

# =============================================================================
# INSTALADORES WEB (desde repos oficiales / internet)
# =============================================================================
instalar_apache_web() {
    print_info "Instalando Apache2 desde repositorios oficiales..."
    apk add --no-cache apache2 apache2-utils > /dev/null 2>&1
    if command -v httpd > /dev/null 2>&1 || [ -f /usr/sbin/httpd ]; then
        print_success "Apache2 instalado desde repositorios oficiales."
    else
        print_warning "Error al instalar Apache2."
        return 1
    fi
}

instalar_nginx_web() {
    print_info "Instalando Nginx desde repositorios oficiales..."
    apk add --no-cache nginx > /dev/null 2>&1
    if command -v nginx > /dev/null 2>&1; then
        print_success "Nginx instalado desde repositorios oficiales."
    else
        print_warning "Error al instalar Nginx."
        return 1
    fi
}

instalar_tomcat_web() {
    version="$1"
    print_info "Instalando Tomcat $version desde internet..."
    apk add --no-cache openjdk17 wget ca-certificates > /dev/null 2>&1
    rc-service tomcat stop 2>/dev/null; sleep 2
    pgrep -f "catalina" > /dev/null 2>&1 && { pkill -9 -f "catalina" 2>/dev/null; sleep 2; }
    if ! id tomcat > /dev/null 2>&1; then
        adduser -D -h /opt/tomcat -s /sbin/nologin tomcat 2>/dev/null
    fi
    major="${version%%.*}"
    cd /tmp || return 1
    descargado=0
    for mirror in \
        "https://dlcdn.apache.org/tomcat/tomcat-${major}/v${version}/bin/apache-tomcat-${version}.tar.gz" \
        "https://archive.apache.org/dist/tomcat/tomcat-${major}/v${version}/bin/apache-tomcat-${version}.tar.gz"; do
        rm -f tomcat.tar.gz
        if wget -q "$mirror" -O tomcat.tar.gz 2>&1 && [ -s tomcat.tar.gz ]; then
            descargado=1; break
        fi
    done
    [ "$descargado" -eq 0 ] && { print_warning "No se pudo descargar Tomcat."; return 1; }
    rm -rf /opt/tomcat; mkdir -p /opt/tomcat
    tar -xzf tomcat.tar.gz -C /opt/tomcat --strip-components=1 2>/dev/null
    rm -f tomcat.tar.gz
    chown -R tomcat:tomcat /opt/tomcat
    chmod -R 750 /opt/tomcat; chmod +x /opt/tomcat/bin/*.sh
    print_success "Tomcat $version instalado desde internet."
}

# =============================================================================
# CONFIGURACION POST-INSTALACION
# =============================================================================
configurar_apache_post() {
    puerto="$1"
    conf="/etc/apache2/httpd.conf"
    [ ! -f "$conf" ] && return 1
    sed -i "s/^Listen .*/Listen $puerto/g" "$conf"
    # Seguridad
    if ! grep -q "ServerTokens Prod" "$conf"; then
        cat >> "$conf" << 'SECEOF'

# P7-Security
ServerTokens Prod
ServerSignature Off
TraceEnable Off
SECEOF
    fi
    version=$(apk info apache2 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [ -z "$version" ] && version="2.4.x"
    crear_index_html "Apache2" "$version" "$puerto" "/var/www/localhost/htdocs"
    chown -R apache:apache /var/www/localhost/htdocs 2>/dev/null
    abrir_puerto_firewall "$puerto"
    rc-update add apache2 default 2>/dev/null
    rc-service apache2 restart 2>/dev/null
    sleep 2
    print_success "Apache2 configurado en puerto $puerto"
}

configurar_nginx_post() {
    puerto="$1"
    mkdir -p /etc/nginx/http.d /var/www/html /var/lib/nginx/tmp /run/nginx
    cat > /etc/nginx/http.d/default.conf << EOF
server {
    listen $puerto;
    server_name _;
    root /var/www/html;
    index index.html;
    location / { try_files \$uri \$uri/ =404; }
}
EOF
    # server_tokens off
    if ! grep -q "server_tokens off" /etc/nginx/nginx.conf 2>/dev/null; then
        sed -i '/http {/a \    server_tokens off;' /etc/nginx/nginx.conf
    fi
    version=$(apk info nginx 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [ -z "$version" ] && version="1.x.x"
    crear_index_html "Nginx" "$version" "$puerto" "/var/www/html"
    chown -R nginx:nginx /var/www/html /var/lib/nginx /run/nginx
    abrir_puerto_firewall "$puerto"
    rc-update add nginx default 2>/dev/null
    rc-service nginx restart 2>/dev/null
    sleep 2
    print_success "Nginx configurado en puerto $puerto"
}

configurar_tomcat_post() {
    puerto="$1"
    conf="/opt/tomcat/conf/server.xml"
    [ ! -f "$conf" ] && return 1
    # Puertos privilegiados
    if [ "$puerto" -lt 1024 ]; then
        sysctl -w net.ipv4.ip_unprivileged_port_start="$puerto" > /dev/null 2>&1
        if ! grep -q "ip_unprivileged_port_start" /etc/sysctl.conf 2>/dev/null; then
            echo "net.ipv4.ip_unprivileged_port_start=$puerto" >> /etc/sysctl.conf
        else
            sed -i "s/net.ipv4.ip_unprivileged_port_start=.*/net.ipv4.ip_unprivileged_port_start=$puerto/" /etc/sysctl.conf
        fi
    fi
    sed -i "s/\(<Connector[^>]*\)port=\"[0-9]*\"/\1port=\"$puerto\"/" "$conf"
    echo "$puerto" > /opt/tomcat/conf/tomcat_port
    # Ocultar version
    if ! grep -q 'server=""' "$conf"; then
        sed -i 's/<Connector port/<Connector server="" port/g' "$conf"
    fi
    # Index
    webapps="/opt/tomcat/webapps/ROOT"
    rm -rf "$webapps"/*
    version=$(cat /opt/tomcat/RELEASE-NOTES 2>/dev/null | grep -oE 'Apache Tomcat Version [0-9.]+' | grep -oE '[0-9.]+' | head -1)
    [ -z "$version" ] && version="10.x"
    crear_index_html "Apache Tomcat" "$version" "$puerto" "$webapps"
    # Renombrar a JSP para que Tomcat lo sirva
    mv "$webapps/index.html" "$webapps/index.jsp" 2>/dev/null
    chown -R tomcat:tomcat /opt/tomcat
    abrir_puerto_firewall "$puerto"
    # Servicio init
    cat > /etc/init.d/tomcat << 'INITEOF'
#!/sbin/openrc-run
description="Apache Tomcat"
export JAVA_HOME=/usr/lib/jvm/default-jvm
export CATALINA_HOME=/opt/tomcat
export CATALINA_PID=/opt/tomcat/temp/tomcat.pid
depend() { need net; }
start() {
    ebegin "Starting Tomcat"
    p=$(cat /opt/tomcat/conf/tomcat_port 2>/dev/null)
    [ -n "$p" ] && [ "$p" -lt 1024 ] && sysctl -w net.ipv4.ip_unprivileged_port_start="$p" >/dev/null 2>&1
    su -s /bin/sh tomcat -c "$CATALINA_HOME/bin/startup.sh"
    eend $?
}
stop() {
    ebegin "Stopping Tomcat"
    su -s /bin/sh tomcat -c "$CATALINA_HOME/bin/shutdown.sh"
    sleep 3; pkill -f "catalina" 2>/dev/null; eend 0
}
INITEOF
    chmod +x /etc/init.d/tomcat
    rc-update add tomcat default 2>/dev/null
    rc-service tomcat restart 2>/dev/null
    sleep 8
    print_success "Tomcat configurado en puerto $puerto"
}

# =============================================================================
# MENU PRINCIPAL DE INSTALACION
# =============================================================================
menu_instalar() {
    print_title "INSTALAR SERVIDOR HTTP"
    print_menu "  [1] Apache2"
    print_menu "  [2] Nginx"
    print_menu "  [3] Tomcat"
    print_menu "  [0] Volver"
    printf "\n${C_PINK}Servicio: ${C_RESET}"
    read sel_srv

    case "$sel_srv" in
        0) return ;;
        1|2|3) ;;
        *) print_warning "Opcion invalida."; return ;;
    esac

    # Elegir puerto HTTP
    case "$sel_srv" in
        1) if ! pedir_puerto 80; then return; fi ;;
        2) if ! pedir_puerto 80; then return; fi ;;
        3) if ! pedir_puerto 8080; then return; fi ;;
    esac
    puerto_http="$PUERTO_ELEGIDO"

    # Elegir fuente
    printf "\n${C_ROSE}  Fuente de instalacion:${C_RESET}\n"
    print_menu "  [1] WEB (repositorios oficiales / internet)"
    print_menu "  [2] FTP (repositorio privado)"
    printf "${C_PINK}Fuente: ${C_RESET}"
    read sel_fuente

    case "$sel_fuente" in
        1)  # INSTALACION DESDE WEB
            case "$sel_srv" in
                1) instalar_apache_web && configurar_apache_post "$puerto_http" ;;
                2) instalar_nginx_web && configurar_nginx_post "$puerto_http" ;;
                3)
                    printf "\n${C_ROSE}  Version de Tomcat:${C_RESET}\n"
                    print_menu "  [1] 10.1.20 (LTS)"
                    print_menu "  [2] 10.1.34 (Latest)"
                    print_menu "  [3] 9.0.96  (Legacy)"
                    printf "${C_PINK}Version: ${C_RESET}"
                    read sel_ver
                    case "$sel_ver" in
                        1) ver="10.1.20" ;; 2) ver="10.1.34" ;; 3) ver="9.0.96" ;;
                        *) print_warning "Invalido"; return ;;
                    esac
                    instalar_tomcat_web "$ver" && configurar_tomcat_post "$puerto_http"
                    ;;
            esac
            ;;
        2)  # INSTALACION DESDE FTP
            if ! navegar_ftp; then return; fi
            if ! descargar_desde_ftp; then return; fi
            case "$sel_srv" in
                1) instalar_apache_local "$ARCHIVO_DESCARGADO" && configurar_apache_post "$puerto_http" ;;
                2) instalar_nginx_local "$ARCHIVO_DESCARGADO" && configurar_nginx_post "$puerto_http" ;;
                3) instalar_tomcat_local "$ARCHIVO_DESCARGADO" && configurar_tomcat_post "$puerto_http" ;;
            esac
            rm -f "$ARCHIVO_DESCARGADO" "/tmp/${ARCHIVO_FTP_ELEGIDO}.sha256"
            ;;
        *) print_warning "Opcion invalida." ;;
    esac

    # Resumen
    IP=$(obtener_ip)
    printf "\n"
    print_success "Servidor instalado y activo en puerto $puerto_http"
    print_info "Accede desde: http://${IP}:$puerto_http"
}