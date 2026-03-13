#!/bin/sh
# =============================================================================
# utilidades.sh — Funciones utilitarias generales
# Proyecto : Aprovisionamiento Web Automatizado
# SO       : Alpine Linux 3.23
# Uso      : source ./lib/utilidades.sh  (no ejecutar directamente)
# =============================================================================

# -----------------------------------------------------------------------------
# COLORES — Blanco, Amarillo y Azul
# -----------------------------------------------------------------------------
C_RESET='\033[0m'
C_WHITE='\033[1;37m'
C_YELLOW='\033[1;33m'
C_BLUE='\033[1;34m'
C_BOLD='\033[1m'

# -----------------------------------------------------------------------------
# FUNCIONES DE IMPRESIÓN
# -----------------------------------------------------------------------------
print_warning() { printf "${C_YELLOW}[ERROR] %s${C_RESET}\n" "$1"; }
print_success() { printf "${C_BLUE}[OK]    %s${C_RESET}\n" "$1"; }
print_info()    { printf "${C_WHITE}[INFO]  %s${C_RESET}\n" "$1"; }
print_menu()    { printf "${C_WHITE}%s${C_RESET}\n" "$1"; }
print_title()   { printf "\n${C_BOLD}${C_BLUE}========================================${C_RESET}\n";
                  printf "${C_BOLD}${C_BLUE}  %s${C_RESET}\n" "$1";
                  printf "${C_BOLD}${C_BLUE}========================================${C_RESET}\n\n"; }

# -----------------------------------------------------------------------------
# VERIFICAR ROOT
# -----------------------------------------------------------------------------
verificar_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_warning "Este script debe ejecutarse como root (usa sudo)"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# VERIFICAR QUE UN COMANDO EXISTE
# -----------------------------------------------------------------------------
requiere_comando() {
    if ! command -v "$1" > /dev/null 2>&1; then
        print_warning "Comando requerido no encontrado: $1"
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# VALIDAR INPUT GENÉRICO
# -----------------------------------------------------------------------------
validar_input() {
    valor="$1"
    campo="$2"

    if [ -z "$valor" ]; then
        print_warning "El campo '$campo' no puede estar vacío."
        return 1
    fi

    if echo "$valor" | grep -qE '[;|&$<>(){}\\`!]'; then
        print_warning "El campo '$campo' contiene caracteres no permitidos."
        return 1
    fi

    return 0
}

# -----------------------------------------------------------------------------
# VALIDAR PUERTO
#
# Puertos BLOQUEADOS:
#   1-1023  — Puertos privilegiados (solo root puede abrirlos).
#             Tomcat corre como usuario no-root, no puede hacer bind.
#             Excepcion: 80 y 443 son validos (Apache/Nginx los abren como root)
#
#   Servicios del sistema reservados:
#   20,21 FTP  22,2122 SSH  23 Telnet  25 SMTP  53 DNS
#   110 POP3  143 IMAP  3306 MySQL  5432 PostgreSQL
#   6379 Redis  27017 MongoDB  40000-40005 rango interno
#
# Puertos RECOMENDADOS para servidores web:
#   8080, 8443, 8888, 9090, 8000, 9000 ...
# -----------------------------------------------------------------------------
validar_puerto() {
    puerto="$1"

    # Validar que sea número
    if ! echo "$puerto" | grep -qE '^[0-9]+$'; then
        print_warning "El puerto debe ser un número entero."
        return 1
    fi

    # Validar rango completo
    if [ "$puerto" -lt 1 ] || [ "$puerto" -gt 65535 ]; then
        print_warning "Puerto $puerto fuera de rango permitido (1-65535)."
        return 1
    fi

    # =========================================================
    # Puertos privilegiados (1-1023) excepto 80 y 443:
    # Requieren cap_net_bind_service en el binario de Java.
    # El script setup_tomcat aplica setcap automaticamente
    # cuando detecta un puerto < 1024.
    # Se permite continuar pero se avisa al usuario.
    # =========================================================
    if [ "$puerto" -lt 1024 ] && [ "$puerto" -ne 80 ] && [ "$puerto" -ne 443 ]; then
        printf "${C_YELLOW}[WARN]  Puerto $puerto es privilegiado (< 1024).${C_RESET}\n"
        printf "${C_YELLOW}[WARN]  El script aplicará cap_net_bind_service a Java automaticamente.${C_RESET}\n"
    fi

    # Puertos reservados para servicios críticos del sistema
    case "$puerto" in
        20|21|22|2122|23|25|53|110|143|3306|5432|6379|27017|40000|40001|40002|40003|40004|40005)
            print_warning "Puerto $puerto reservado para otro servicio del sistema."
            return 1
            ;;
    esac

    # Verificar que no esté ocupado
    if netstat -tuln 2>/dev/null | grep -q ":${puerto} " || \
       ss    -tuln 2>/dev/null | grep -q ":${puerto} "; then
        proceso=$(netstat -tulnp 2>/dev/null | grep ":${puerto} " | awk '{print $7}' | head -1)
        print_warning "Puerto $puerto ya está en uso."
        if [ -n "$proceso" ]; then
            print_warning "Proceso: $proceso"
        fi
        return 1
    fi

    print_success "Puerto $puerto disponible."
    return 0
}

# -----------------------------------------------------------------------------
# PEDIR PUERTO AL USUARIO (con reintentos)
# -----------------------------------------------------------------------------
pedir_puerto() {
    intentos=0
    max_intentos=3

    while [ "$intentos" -lt "$max_intentos" ]; do
        printf "${C_YELLOW}Ingresa el puerto de escucha (ej. 8080, 8888): ${C_RESET}"
        read puerto_raw

        if validar_input "$puerto_raw" "puerto" && validar_puerto "$puerto_raw"; then
            PUERTO_ELEGIDO="$puerto_raw"
            export PUERTO_ELEGIDO
            return 0
        fi

        intentos=$((intentos + 1))
        print_info "Intento $intentos de $max_intentos."
    done

    print_warning "Demasiados intentos fallidos al ingresar el puerto."
    return 1
}

# -----------------------------------------------------------------------------
# ABRIR PUERTO EN FIREWALL (iptables — Alpine)
# -----------------------------------------------------------------------------
abrir_puerto_firewall() {
    puerto="$1"

    print_info "Configurando firewall para puerto $puerto..."

    if ! requiere_comando "iptables"; then
        apk add --no-cache iptables ip6tables > /dev/null 2>&1
    fi

    if ! iptables -C INPUT -p tcp --dport "$puerto" -j ACCEPT 2>/dev/null; then
        iptables -A INPUT -p tcp --dport "$puerto" -j ACCEPT
        print_success "Puerto $puerto abierto en firewall."
    else
        print_info "Puerto $puerto ya estaba abierto."
    fi

    if [ "$puerto" -ne 80 ]; then
        if iptables -C INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null; then
            iptables -D INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null
            print_info "Puerto 80 cerrado (no utilizado)."
        fi
    fi

    if [ "$puerto" -ne 443 ]; then
        if iptables -C INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null; then
            iptables -D INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null
            print_info "Puerto 443 cerrado (no utilizado)."
        fi
    fi

    if command -v rc-service > /dev/null 2>&1; then
        rc-service iptables save 2>/dev/null
        print_success "Reglas de firewall guardadas."
    fi
}

# -----------------------------------------------------------------------------
# CREAR USUARIO DEDICADO PARA UN SERVICIO
# -----------------------------------------------------------------------------
crear_usuario_servicio() {
    usuario="$1"
    directorio="$2"

    if id "$usuario" > /dev/null 2>&1; then
        print_info "Usuario '$usuario' ya existe."
    else
        print_info "Creando usuario dedicado '$usuario'..."
        adduser -D -H -s /sbin/nologin "$usuario" 2>/dev/null
        print_success "Usuario '$usuario' creado."
    fi

    if [ -d "$directorio" ]; then
        chown -R "${usuario}:${usuario}" "$directorio"
        chmod 750 "$directorio"
        print_success "Permisos aplicados en $directorio para '$usuario'."
    fi
}

# -----------------------------------------------------------------------------
# CREAR INDEX.HTML PERSONALIZADO
# -----------------------------------------------------------------------------
crear_index() {
    servicio="$1"
    version="$2"
    puerto="$3"
    ruta_web="$4"

    mkdir -p "$ruta_web"

    cat > "${ruta_web}/index.html" << EOF
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
    <h1>$servicio</h1>
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

    print_success "index.html creado en $ruta_web"
}

# -----------------------------------------------------------------------------
# PAUSAR HASTA QUE EL USUARIO PRESIONE ENTER
# -----------------------------------------------------------------------------
pausar() {
    printf "\n${C_YELLOW}Presiona Enter para continuar...${C_RESET}"
    read pausa
}