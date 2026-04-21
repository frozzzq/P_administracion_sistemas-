#!/bin/sh
# =============================================================================
# p7_ssl.sh — Configuracion SSL/TLS para los 4 servicios
# Apache, Nginx, Tomcat (HTTPS) + vsftpd (FTPS)
# Certificados autofirmados para reprobados.com
# SO: Alpine Linux 3.23
# =============================================================================

SSL_CERT="/etc/ssl/certs/reprobados.crt"
SSL_KEY="/etc/ssl/private/reprobados.key"
SSL_DOMAIN="reprobados.com"
TOMCAT_KEYSTORE="/opt/tomcat/conf/keystore.jks"

# =============================================================================
# GENERAR CERTIFICADO AUTOFIRMADO
# =============================================================================
generar_certificado_ssl() {
    print_info "Generando certificado SSL para $SSL_DOMAIN ..."

    apk add --no-cache openssl > /dev/null 2>&1
    mkdir -p /etc/ssl/private /etc/ssl/certs

    # Verificar si ya existe
    if [ -f "$SSL_CERT" ] && [ -f "$SSL_KEY" ]; then
        printf "${C_PINK}Ya existe un certificado. Regenerar? [s/N]: ${C_RESET}"
        read regen
        if ! echo "$regen" | grep -qiE '^s$'; then
            print_info "Usando certificado existente."
            return 0
        fi
    fi

    # Generar certificado autofirmado
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$SSL_KEY" \
        -out "$SSL_CERT" \
        -subj "/C=MX/ST=Sinaloa/L=Los Mochis/O=Reprobados/OU=IT/CN=$SSL_DOMAIN" \
        2>/dev/null

    if [ -f "$SSL_CERT" ] && [ -f "$SSL_KEY" ]; then
        chmod 600 "$SSL_KEY"
        chmod 644 "$SSL_CERT"
        print_success "Certificado generado:"
        print_success "  Cert: $SSL_CERT"
        print_success "  Key:  $SSL_KEY"
        print_info "  Dominio: $SSL_DOMAIN"
        print_info "  Validez: 365 dias"
        return 0
    else
        print_warning "Error al generar certificado."
        return 1
    fi
}

# =============================================================================
# SSL EN APACHE
# =============================================================================
configurar_ssl_apache() {
    print_title "SSL/TLS EN APACHE"

    # Verificar que Apache esta instalado
    if ! rc-service apache2 status > /dev/null 2>&1 && ! [ -f /etc/apache2/httpd.conf ]; then
        print_warning "Apache no esta instalado. Instalalo primero."
        return 1
    fi

    # Generar certificado si no existe
    if [ ! -f "$SSL_CERT" ] || [ ! -f "$SSL_KEY" ]; then
        generar_certificado_ssl || return 1
    fi

    # Pedir puerto HTTPS
    if ! pedir_puerto_ssl; then return 1; fi
    puerto_ssl="$PUERTO_SSL"

    # Instalar mod_ssl y dependencias
    print_info "Instalando mod_ssl..."
    apk add --no-cache apache2-ssl > /dev/null 2>&1

    conf="/etc/apache2/httpd.conf"

    # =========================================================
    # FIX: En Alpine, LoadModule ssl_module puede NO existir
    # en httpd.conf (ni siquiera comentada). Hay que asegurar
    # que los modulos criticos esten cargados:
    #   - mod_ssl.so        (SSLEngine, SSLCertificateFile)
    #   - mod_socache_shmcb (SSLSessionCache)
    #   - mod_headers       (Header always set)
    #   - mod_rewrite       (Redirect)
    # =========================================================
    for mod_line in \
        "LoadModule ssl_module modules/mod_ssl.so" \
        "LoadModule socache_shmcb_module modules/mod_socache_shmcb.so" \
        "LoadModule headers_module modules/mod_headers.so" \
        "LoadModule rewrite_module modules/mod_rewrite.so"; do

        mod_name=$(echo "$mod_line" | awk '{print $2}')

        # Caso 1: esta comentada -> descomentar
        if grep -q "^#.*LoadModule $mod_name" "$conf" 2>/dev/null; then
            sed -i "s|^#.*LoadModule $mod_name.*|$mod_line|" "$conf"
            print_info "  Descomentado: $mod_name"
        # Caso 2: ya esta activa -> no hacer nada
        elif grep -q "^LoadModule $mod_name" "$conf" 2>/dev/null; then
            print_info "  Ya cargado: $mod_name"
        # Caso 3: no existe en absoluto -> agregar al final
        else
            echo "$mod_line" >> "$conf"
            print_info "  Agregado: $mod_name"
        fi
    done

    # Verificar que los .so existen fisicamente
    for so in mod_ssl.so mod_socache_shmcb.so mod_headers.so; do
        ruta_so=$(find /usr/lib/apache2 -name "$so" 2>/dev/null | head -1)
        if [ -z "$ruta_so" ]; then
            print_warning "Modulo $so no encontrado en disco. Instalacion de apache2-ssl incompleta."
            return 1
        fi
    done
    print_success "Todos los modulos SSL cargados correctamente."

    # Obtener puerto HTTP actual
    puerto_http=$(grep "^Listen" "$conf" | grep -v "$puerto_ssl" | awk '{print $2}' | head -1)
    [ -z "$puerto_http" ] && puerto_http="80"

    # Eliminar configuracion SSL anterior si existe
    rm -f /etc/apache2/conf.d/p7-ssl.conf
    # Tambien eliminar ssl.conf default que puede crear apache2-ssl
    rm -f /etc/apache2/conf.d/ssl.conf

    # Crear configuracion SSL limpia
    ssl_conf="/etc/apache2/conf.d/p7-ssl.conf"
    cat > "$ssl_conf" << EOF
Listen $puerto_ssl

<VirtualHost *:$puerto_ssl>
    ServerName $SSL_DOMAIN
    DocumentRoot /var/www/localhost/htdocs

    SSLEngine on
    SSLCertificateFile $SSL_CERT
    SSLCertificateKeyFile $SSL_KEY

    SSLProtocol all -SSLv2 -SSLv3
    SSLCipherSuite HIGH:!aNULL:!MD5

    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
</VirtualHost>

# Redireccion HTTP -> HTTPS
<VirtualHost *:$puerto_http>
    ServerName $SSL_DOMAIN
    Redirect permanent / https://$SSL_DOMAIN:$puerto_ssl/
</VirtualHost>
EOF

    abrir_puerto_firewall "$puerto_ssl"

    # Validar config
    if httpd -t 2>&1 | grep -q "Syntax OK"; then
        print_success "Configuracion Apache SSL validada."
    else
        print_warning "Error en configuracion Apache:"
        httpd -t
        return 1
    fi

    rc-service apache2 restart 2>/dev/null
    sleep 2
    print_success "Apache SSL activo en puerto $puerto_ssl"
    print_info "Redireccion HTTP ($puerto_http) -> HTTPS ($puerto_ssl) configurada."
}

# =============================================================================
# SSL EN NGINX
# =============================================================================
configurar_ssl_nginx() {
    print_title "SSL/TLS EN NGINX"

    if ! command -v nginx > /dev/null 2>&1; then
        print_warning "Nginx no esta instalado. Instalalo primero."
        return 1
    fi

    if [ ! -f "$SSL_CERT" ] || [ ! -f "$SSL_KEY" ]; then
        generar_certificado_ssl || return 1
    fi

    if ! pedir_puerto_ssl; then return 1; fi
    puerto_ssl="$PUERTO_SSL"

    # Leer puerto HTTP actual
    puerto_http=$(grep "listen" /etc/nginx/http.d/default.conf 2>/dev/null | grep -v ssl | grep -oE '[0-9]+' | head -1)
    [ -z "$puerto_http" ] && puerto_http="80"

    # Reescribir configuracion con SSL + redirect
    cat > /etc/nginx/http.d/default.conf << EOF
# Redireccion HTTP -> HTTPS
server {
    listen $puerto_http;
    server_name $SSL_DOMAIN _;
    return 301 https://\$host:$puerto_ssl\$request_uri;
}

# Servidor HTTPS
server {
    listen $puerto_ssl ssl;
    server_name $SSL_DOMAIN _;

    ssl_certificate $SSL_CERT;
    ssl_certificate_key $SSL_KEY;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # HSTS
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;

    root /var/www/html;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

    abrir_puerto_firewall "$puerto_ssl"

    if nginx -t 2>&1 | grep -q "successful"; then
        print_success "Configuracion Nginx SSL validada."
    else
        print_warning "Error en configuracion Nginx:"
        nginx -t
        return 1
    fi

    rc-service nginx restart 2>/dev/null
    sleep 2
    print_success "Nginx SSL activo en puerto $puerto_ssl"
    print_info "Redireccion HTTP ($puerto_http) -> HTTPS ($puerto_ssl) configurada."
}

# =============================================================================
# SSL EN TOMCAT
# =============================================================================
configurar_ssl_tomcat() {
    print_title "SSL/TLS EN TOMCAT"

    if [ ! -d /opt/tomcat ]; then
        print_warning "Tomcat no esta instalado. Instalalo primero."
        return 1
    fi

    if [ ! -f "$SSL_CERT" ] || [ ! -f "$SSL_KEY" ]; then
        generar_certificado_ssl || return 1
    fi

    if ! pedir_puerto_ssl; then return 1; fi
    puerto_ssl="$PUERTO_SSL"

    # Puerto privilegiado
    if [ "$puerto_ssl" -lt 1024 ]; then
        sysctl -w net.ipv4.ip_unprivileged_port_start="$puerto_ssl" > /dev/null 2>&1
        sed -i "s/net.ipv4.ip_unprivileged_port_start=.*/net.ipv4.ip_unprivileged_port_start=$puerto_ssl/" /etc/sysctl.conf 2>/dev/null
    fi

    # Generar keystore Java a partir del certificado PEM
    print_info "Generando keystore Java..."
    apk add --no-cache openjdk17 > /dev/null 2>&1
    rm -f /tmp/reprobados.p12 "$TOMCAT_KEYSTORE"

    openssl pkcs12 -export \
        -in "$SSL_CERT" \
        -inkey "$SSL_KEY" \
        -out /tmp/reprobados.p12 \
        -name tomcat \
        -password pass:changeit 2>/dev/null

    keytool -importkeystore \
        -srckeystore /tmp/reprobados.p12 \
        -srcstoretype PKCS12 \
        -srcstorepass changeit \
        -destkeystore "$TOMCAT_KEYSTORE" \
        -deststoretype JKS \
        -deststorepass changeit \
        -noprompt 2>/dev/null

    rm -f /tmp/reprobados.p12

    if [ -f "$TOMCAT_KEYSTORE" ]; then
        chown tomcat:tomcat "$TOMCAT_KEYSTORE"
        chmod 600 "$TOMCAT_KEYSTORE"
        print_success "Keystore generado: $TOMCAT_KEYSTORE"
    else
        print_warning "Error al generar keystore."
        return 1
    fi

    # Leer puerto HTTP actual
    conf="/opt/tomcat/conf/server.xml"
    puerto_http=$(grep 'Connector.*port=' "$conf" | grep -v SSL | grep -v "8443" | grep -oE 'port="[0-9]+"' | head -1 | grep -oE '[0-9]+')
    [ -z "$puerto_http" ] && puerto_http="8080"

    # Agregar Connector HTTPS si no existe
    if ! grep -q "SSLEnabled=\"true\"" "$conf"; then
        sed -i "/<Service name=\"Catalina\">/a\\
\\
    <!-- HTTPS Connector - P7 SSL -->\\
    <Connector port=\"$puerto_ssl\" protocol=\"org.apache.coyote.http11.Http11NioProtocol\"\\
               maxThreads=\"150\" SSLEnabled=\"true\">\\
        <SSLHostConfig>\\
            <Certificate certificateKeystoreFile=\"$TOMCAT_KEYSTORE\"\\
                         certificateKeystorePassword=\"changeit\"\\
                         type=\"RSA\" />\\
        </SSLHostConfig>\\
    </Connector>" "$conf"
        print_success "Connector HTTPS agregado en puerto $puerto_ssl"
    else
        # Actualizar puerto SSL existente
        sed -i "s/\(SSLEnabled=\"true\"[^>]*\)port=\"[0-9]*\"/\1port=\"$puerto_ssl\"/" "$conf"
        print_info "Puerto SSL actualizado a $puerto_ssl"
    fi

    # Redireccion HTTP -> HTTPS en web.xml
    webxml="/opt/tomcat/conf/web.xml"
    if ! grep -q "CONFIDENTIAL" "$webxml" 2>/dev/null; then
        # Insertar antes del cierre </web-app>
        sed -i "/<\/web-app>/i\\
\\
    <!-- P7: Redireccion HTTP -> HTTPS -->\\
    <security-constraint>\\
        <web-resource-collection>\\
            <web-resource-name>SSL Redirect</web-resource-name>\\
            <url-pattern>/*</url-pattern>\\
        </web-resource-collection>\\
        <user-data-constraint>\\
            <transport-guarantee>CONFIDENTIAL</transport-guarantee>\\
        </user-data-constraint>\\
    </security-constraint>" "$webxml"
        print_success "Redireccion HTTP -> HTTPS configurada en web.xml"
    fi

    chown -R tomcat:tomcat /opt/tomcat
    abrir_puerto_firewall "$puerto_ssl"
    rc-service tomcat restart 2>/dev/null
    sleep 8
    print_success "Tomcat SSL activo en puerto $puerto_ssl"
    print_info "Redireccion HTTP ($puerto_http) -> HTTPS ($puerto_ssl) configurada."
}

# =============================================================================
# SSL EN VSFTPD (FTPS)
# =============================================================================
configurar_ssl_vsftpd() {
    print_title "SSL/TLS EN VSFTPD (FTPS)"

    if ! command -v vsftpd > /dev/null 2>&1; then
        print_warning "vsftpd no esta instalado. Ejecuta el script de la Practica 5 primero."
        return 1
    fi

    if [ ! -f "$SSL_CERT" ] || [ ! -f "$SSL_KEY" ]; then
        generar_certificado_ssl || return 1
    fi

    conf="/etc/vsftpd/vsftpd.conf"
    if [ ! -f "$conf" ]; then
        print_warning "Archivo de configuracion no encontrado: $conf"
        return 1
    fi

    # Eliminar configuracion SSL anterior si existe
    sed -i '/^# P7-SSL/,/^# P7-SSL-END/d' "$conf"
    sed -i '/^ssl_enable/d; /^rsa_cert_file/d; /^rsa_private_key_file/d' "$conf"
    sed -i '/^force_local_data_ssl/d; /^force_local_logins_ssl/d' "$conf"
    sed -i '/^ssl_tlsv1/d; /^ssl_sslv2/d; /^ssl_sslv3/d; /^ssl_ciphers/d' "$conf"
    sed -i '/^require_ssl_reuse/d; /^allow_anon_ssl/d; /^implicit_ssl/d' "$conf"

    # Agregar configuracion SSL
    cat >> "$conf" << EOF

# P7-SSL
ssl_enable=YES
rsa_cert_file=$SSL_CERT
rsa_private_key_file=$SSL_KEY
allow_anon_ssl=NO
force_local_data_ssl=YES
force_local_logins_ssl=YES
ssl_tlsv1=YES
ssl_sslv2=NO
ssl_sslv3=NO
ssl_ciphers=HIGH
require_ssl_reuse=NO
implicit_ssl=NO
# P7-SSL-END
EOF

    # Asegurar seccomp_sandbox=NO (necesario en Alpine)
    if ! grep -q "seccomp_sandbox=NO" "$conf"; then
        echo "seccomp_sandbox=NO" >> "$conf"
    fi

    rc-service vsftpd restart 2>/dev/null
    sleep 2

    if rc-service vsftpd status > /dev/null 2>&1; then
        print_success "vsftpd FTPS activo."
        print_info "Los usuarios locales ahora requieren conexion cifrada."
        print_info "Configura FileZilla con: Protocolo FTPS (FTP sobre TLS explicito)"
    else
        print_warning "vsftpd no arranco. Revisa: tail -20 /var/log/vsftpd.log"
        return 1
    fi
}

# =============================================================================
# MENU SSL
# =============================================================================
menu_ssl() {
    print_title "CONFIGURAR SSL/TLS"
    print_menu "  [1] Generar certificado autofirmado"
    print_menu "  [2] SSL en Apache (HTTPS)"
    print_menu "  [3] SSL en Nginx (HTTPS)"
    print_menu "  [4] SSL en Tomcat (HTTPS)"
    print_menu "  [5] SSL en vsftpd (FTPS)"
    print_menu "  [6] Configurar TODOS"
    print_menu "  [0] Volver"
    printf "\n${C_PINK}Opcion: ${C_RESET}"
    read sel

    case "$sel" in
        1) generar_certificado_ssl ;;
        2) configurar_ssl_apache ;;
        3) configurar_ssl_nginx ;;
        4) configurar_ssl_tomcat ;;
        5) configurar_ssl_vsftpd ;;
        6)
            generar_certificado_ssl
            printf "\n${C_PINK}Configurar SSL en Apache? [s/N]: ${C_RESET}"; read r
            echo "$r" | grep -qiE '^s$' && configurar_ssl_apache
            printf "\n${C_PINK}Configurar SSL en Nginx? [s/N]: ${C_RESET}"; read r
            echo "$r" | grep -qiE '^s$' && configurar_ssl_nginx
            printf "\n${C_PINK}Configurar SSL en Tomcat? [s/N]: ${C_RESET}"; read r
            echo "$r" | grep -qiE '^s$' && configurar_ssl_tomcat
            printf "\n${C_PINK}Configurar SSL en vsftpd? [s/N]: ${C_RESET}"; read r
            echo "$r" | grep -qiE '^s$' && configurar_ssl_vsftpd
            ;;
        0) return ;;
        *) print_warning "Opcion invalida." ;;
    esac
}

# =============================================================================
# VERIFICACION Y RESUMEN DE TODOS LOS SERVICIOS SSL
# =============================================================================
verificar_todos_ssl() {
    print_title "RESUMEN DE SERVICIOS SSL/TLS"

    apk add --no-cache curl openssl > /dev/null 2>&1

    total=0; exitosos=0

    printf "\n  ${C_BOLD}%-12s %-8s %-10s %-22s %-10s${C_RESET}\n" "SERVICIO" "PUERTO" "ESTADO" "CERTIFICADO" "HSTS"
    printf "  %-12s %-8s %-10s %-22s %-10s\n" "--------" "------" "------" "-----------" "----"

    # ---- Apache HTTPS ----
    total=$((total + 1))
    puerto_a=$(grep "^Listen" /etc/apache2/conf.d/p7-ssl.conf 2>/dev/null | awk '{print $2}' | head -1)
    if [ -n "$puerto_a" ] && curl -sk --connect-timeout 3 "https://localhost:$puerto_a" > /dev/null 2>&1; then
        cn=$(echo | openssl s_client -connect "localhost:$puerto_a" -servername "$SSL_DOMAIN" 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | grep -oE 'CN = [^/,]+' | sed 's/CN = //')
        hsts=$(curl -skI "https://localhost:$puerto_a" 2>/dev/null | grep -ci "Strict-Transport")
        [ "$hsts" -gt 0 ] && hsts_txt="${C_GREEN}SI${C_RESET}" || hsts_txt="${C_HOTPINK}NO${C_RESET}"
        printf "  ${C_GREEN}%-12s${C_RESET} %-8s ${C_GREEN}%-10s${C_RESET} %-22s " "Apache" "$puerto_a" "ACTIVO" "$cn"
        printf "$hsts_txt\n"
        exitosos=$((exitosos + 1))
    else
        printf "  ${C_HOTPINK}%-12s${C_RESET} %-8s ${C_HOTPINK}%-10s${C_RESET} %-22s %-10s\n" "Apache" "${puerto_a:-N/A}" "INACTIVO" "-" "-"
    fi

    # ---- Nginx HTTPS ----
    total=$((total + 1))
    puerto_n=$(grep "listen.*ssl" /etc/nginx/http.d/default.conf 2>/dev/null | grep -oE '[0-9]+' | head -1)
    if [ -n "$puerto_n" ] && curl -sk --connect-timeout 3 "https://localhost:$puerto_n" > /dev/null 2>&1; then
        cn=$(echo | openssl s_client -connect "localhost:$puerto_n" -servername "$SSL_DOMAIN" 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | grep -oE 'CN = [^/,]+' | sed 's/CN = //')
        hsts=$(curl -skI "https://localhost:$puerto_n" 2>/dev/null | grep -ci "Strict-Transport")
        [ "$hsts" -gt 0 ] && hsts_txt="${C_GREEN}SI${C_RESET}" || hsts_txt="${C_HOTPINK}NO${C_RESET}"
        printf "  ${C_GREEN}%-12s${C_RESET} %-8s ${C_GREEN}%-10s${C_RESET} %-22s " "Nginx" "$puerto_n" "ACTIVO" "$cn"
        printf "$hsts_txt\n"
        exitosos=$((exitosos + 1))
    else
        printf "  ${C_HOTPINK}%-12s${C_RESET} %-8s ${C_HOTPINK}%-10s${C_RESET} %-22s %-10s\n" "Nginx" "${puerto_n:-N/A}" "INACTIVO" "-" "-"
    fi

    # ---- Tomcat HTTPS ----
    total=$((total + 1))
    puerto_t=$(grep "SSLEnabled" /opt/tomcat/conf/server.xml 2>/dev/null | grep -oE 'port="[0-9]+"' | grep -oE '[0-9]+' | head -1)
    if [ -n "$puerto_t" ] && curl -sk --connect-timeout 5 "https://localhost:$puerto_t" > /dev/null 2>&1; then
        cn=$(echo | openssl s_client -connect "localhost:$puerto_t" -servername "$SSL_DOMAIN" 2>/dev/null | openssl x509 -noout -subject 2>/dev/null | grep -oE 'CN = [^/,]+' | sed 's/CN = //')
        printf "  ${C_GREEN}%-12s${C_RESET} %-8s ${C_GREEN}%-10s${C_RESET} %-22s %-10s\n" "Tomcat" "$puerto_t" "ACTIVO" "$cn" "via web.xml"
        exitosos=$((exitosos + 1))
    else
        printf "  ${C_HOTPINK}%-12s${C_RESET} %-8s ${C_HOTPINK}%-10s${C_RESET} %-22s %-10s\n" "Tomcat" "${puerto_t:-N/A}" "INACTIVO" "-" "-"
    fi

    # ---- vsftpd FTPS ----
    total=$((total + 1))
    if grep -q "ssl_enable=YES" /etc/vsftpd/vsftpd.conf 2>/dev/null && rc-service vsftpd status > /dev/null 2>&1; then
        cn=$(openssl s_client -connect "localhost:21" -starttls ftp 2>/dev/null < /dev/null | openssl x509 -noout -subject 2>/dev/null | grep -oE 'CN = [^/,]+' | sed 's/CN = //')
        [ -z "$cn" ] && cn="$SSL_DOMAIN"
        printf "  ${C_GREEN}%-12s${C_RESET} %-8s ${C_GREEN}%-10s${C_RESET} %-22s %-10s\n" "vsftpd" "21" "FTPS" "$cn" "N/A"
        exitosos=$((exitosos + 1))
    else
        printf "  ${C_HOTPINK}%-12s${C_RESET} %-8s ${C_HOTPINK}%-10s${C_RESET} %-22s %-10s\n" "vsftpd" "21" "SIN SSL" "-" "-"
    fi

    # Resumen
    printf "\n"
    if [ "$exitosos" -eq "$total" ]; then
        print_success "Todos los servicios ($exitosos/$total) tienen SSL activo."
    else
        print_warning "$exitosos de $total servicios con SSL activo."
    fi

    # Info del certificado
    if [ -f "$SSL_CERT" ]; then
        printf "\n${C_ROSE}  Informacion del certificado:${C_RESET}\n"
        fecha_exp=$(openssl x509 -in "$SSL_CERT" -noout -enddate 2>/dev/null | cut -d= -f2)
        subject=$(openssl x509 -in "$SSL_CERT" -noout -subject 2>/dev/null | sed 's/subject=/  /')
        printf "    Sujeto: %s\n" "$subject"
        printf "    Expira: %s\n" "$fecha_exp"
        printf "    Archivo: %s\n" "$SSL_CERT"
    fi
}