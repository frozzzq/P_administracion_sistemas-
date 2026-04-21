#!/bin/sh
# ============================================================================
# Script de Automatizacion de Servidor FTP - Alpine Linux
# Administracion de Sistemas - vsftpd
# ============================================================================

C_RESET='\033[0m'
C_CYAN='\033[0;36m'
C_GREEN='\033[0;32m'
C_RED='\033[0;31m'
C_YELLOW='\033[0;33m'
C_BOLD='\033[1m'

print_info()   { printf "${C_CYAN}[INFO]  %s${C_RESET}\n" "$1"; }
print_ok()     { printf "${C_GREEN}[OK]    %s${C_RESET}\n" "$1"; }
print_error()  { printf "${C_RED}[ERROR] %s${C_RESET}\n" "$1"; }
print_warn()   { printf "${C_YELLOW}[WARN]  %s${C_RESET}\n" "$1"; }
print_titulo() { printf "\n${C_BOLD}${C_YELLOW}=== %s ===${C_RESET}\n\n" "$1"; }

if [ "$(id -u)" -ne 0 ]; then
    print_error "Este script debe ejecutarse como root (usa sudo o inicia sesion como root)"
    exit 1
fi

FTP_ROOT="/srv/ftp"
USERS_ROOT="/srv/ftp/users"
PUB_ROOT="/srv/ftp/pub"
GENERAL_DIR="/srv/ftp/pub/general"
GRUPO_REPROBADOS="reprobados"
GRUPO_RECURSADORES="recursadores"
GRUPO_FTP="ftp-data"
VSFTPD_CONF="/etc/vsftpd/vsftpd.conf"

verificar_instalacion() {
    print_info "Verificando instalacion de vsftpd..."
    if command -v vsftpd > /dev/null 2>&1; then
        print_ok "vsftpd esta instalado."
        return 0
    else
        print_error "vsftpd no esta instalado."
        return 1
    fi
}

configurar_firewall() {
    print_info "Configurando firewall..."
    if ! iptables -C INPUT -p tcp --dport 21 -j ACCEPT 2>/dev/null; then
        iptables -A INPUT -p tcp --dport 21 -j ACCEPT
        print_ok "Puerto 21 abierto."
    else
        print_info "Regla puerto 21 ya existe."
    fi
    if ! iptables -C INPUT -p tcp --dport 40000:40100 -j ACCEPT 2>/dev/null; then
        iptables -A INPUT -p tcp --dport 40000:40100 -j ACCEPT
        print_ok "Puertos pasivos 40000-40100 abiertos."
    else
        print_info "Regla puertos pasivos ya existe."
    fi
    if command -v rc-service > /dev/null 2>&1; then
        rc-service iptables save 2>/dev/null || true
    fi
}

crear_grupos() {
    print_info "Verificando grupos del sistema..."
    for grupo in "$GRUPO_REPROBADOS" "$GRUPO_RECURSADORES" "$GRUPO_FTP"; do
        if ! getent group "$grupo" > /dev/null 2>&1; then
            addgroup "$grupo"
            print_ok "Grupo '$grupo' creado."
        else
            print_info "Grupo '$grupo' ya existe."
        fi
    done
}


# ============================================================================
# FUNCION: Aplicar permisos recursivos en carpetas compartidas
# Usa ACLs por defecto (setfacl) para que CUALQUIER subcarpeta nueva
# creada dentro de general o de grupos herede los permisos correctos
# automaticamente, sin importar en que nivel de profundidad este.
# ============================================================================
aplicar_permisos_recursivos() {
    DIR="$1"
    GRUPO="$2"

    if ! command -v setfacl > /dev/null 2>&1; then
        print_warn "setfacl no disponible. Instalando paquete acl..."
        apk add acl > /dev/null 2>&1
    fi

    # Verificar que el filesystem soporta ACLs (debe estar montado con opcion acl)
    if ! setfacl -m "g:${GRUPO}:rwx" "$DIR" 2>/dev/null; then
        print_warn "El filesystem no soporta ACLs. Activando..."
        # Remontar con soporte ACL si es posible
        MOUNT_POINT=$(df "$DIR" | tail -1 | awk '{print $6}')
        mount -o remount,acl "$MOUNT_POINT" 2>/dev/null || true
    fi

    # ---- ACLs en contenido EXISTENTE (recursivo) ----
    # Directorios: rwx para poder entrar y crear dentro
    find "$DIR" -type d -exec setfacl -m "g:${GRUPO}:rwx" {} \; 2>/dev/null
    # Archivos: rw para poder leer y modificar
    find "$DIR" -type f -exec setfacl -m "g:${GRUPO}:rw" {} \; 2>/dev/null

    # ---- ACLs POR DEFECTO (heredadas por contenido NUEVO) ----
    # Cualquier carpeta o archivo creado dentro heredara estas reglas
    # automaticamente, sin importar cuantos niveles de profundidad tenga
    find "$DIR" -type d -exec setfacl -m "d:g:${GRUPO}:rwx" {} \; 2>/dev/null

    print_ok "Permisos recursivos (ACL) aplicados en '$DIR' para grupo '$GRUPO'."
}

crear_estructura_base() {
    print_info "Creando estructura de directorios..."
    for dir in "$FTP_ROOT" "$USERS_ROOT" "$PUB_ROOT" "$GENERAL_DIR" \
               "$FTP_ROOT/$GRUPO_REPROBADOS" "$FTP_ROOT/$GRUPO_RECURSADORES"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            print_ok "Creado: $dir"
        else
            print_info "Ya existe: $dir"
        fi
    done
    chown root:root "$FTP_ROOT"
    chmod 755 "$FTP_ROOT"
    chown root:ftp "$PUB_ROOT"
    chmod 755 "$PUB_ROOT"
    chown root:"$GRUPO_FTP" "$GENERAL_DIR"
    chmod 3775 "$GENERAL_DIR"
    print_ok "Permisos 'general' configurados (sticky + setgid activos)."
    chown root:"$GRUPO_REPROBADOS" "$FTP_ROOT/$GRUPO_REPROBADOS"
    chmod 3770 "$FTP_ROOT/$GRUPO_REPROBADOS"
    print_ok "Permisos '$GRUPO_REPROBADOS' configurados."
    chown root:"$GRUPO_RECURSADORES" "$FTP_ROOT/$GRUPO_RECURSADORES"
    chmod 3770 "$FTP_ROOT/$GRUPO_RECURSADORES"
    print_ok "Permisos '$GRUPO_RECURSADORES' configurados."
    chown root:root "$USERS_ROOT"
    chmod 755 "$USERS_ROOT"

    # Aplicar ACLs recursivas para que subcarpetas nuevas hereden permisos
    aplicar_permisos_recursivos "$GENERAL_DIR"           "$GRUPO_FTP"
    aplicar_permisos_recursivos "$FTP_ROOT/$GRUPO_REPROBADOS"  "$GRUPO_REPROBADOS"
    aplicar_permisos_recursivos "$FTP_ROOT/$GRUPO_RECURSADORES" "$GRUPO_RECURSADORES"

    print_ok "Estructura base lista."
}

# ============================================================================
# FIX 1: seccomp_sandbox=NO incluido en el template
# Sin esta linea, vsftpd se cae silenciosamente en Alpine al reiniciarse
# ============================================================================
configurar_vsftpd() {
    print_info "Generando configuracion de vsftpd..."
    mkdir -p /etc/vsftpd
    cat > "$VSFTPD_CONF" << 'EOF'
listen=YES
listen_ipv6=NO
anonymous_enable=YES
anon_root=/srv/ftp/pub
no_anon_password=YES
anon_upload_enable=NO
anon_mkdir_write_enable=NO
anon_other_write_enable=NO
local_enable=YES
write_enable=YES
local_umask=002
chroot_local_user=YES
allow_writeable_chroot=YES
user_sub_token=$USER
local_root=/srv/ftp/users/$USER
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100
userlist_enable=YES
userlist_file=/etc/vsftpd/user_list
userlist_deny=YES
xferlog_enable=YES
xferlog_file=/var/log/vsftpd.log
xferlog_std_format=YES
ftpd_banner=Servidor FTP - Acceso restringido
dirmessage_enable=YES
seccomp_sandbox=NO
EOF
    if [ ! -f /etc/vsftpd/user_list ]; then
        printf 'root\ndaemon\nbin\nsys\nsync\ngames\nman\nlp\nmail\nnews\nuucp\nnobody\n' > /etc/vsftpd/user_list
        print_ok "Lista de bloqueo de usuarios del sistema creada."
    fi
    print_ok "Configuracion vsftpd generada en $VSFTPD_CONF"
}

# ============================================================================
# FIX 2: Usar /proc/mounts en lugar de "mount | grep"
# En Alpine/BusyBox el formato de "mount" puede variar y causar
# falsos positivos/negativos. /proc/mounts es siempre confiable.
# ============================================================================
esta_montado() {
    # Comprueba si DST ya tiene un bind mount activo usando /proc/mounts
    # que es el archivo del kernel, independiente de la herramienta "mount"
    DST="$1"
    # Normalizar la ruta (quitar slash final si existe)
    DST="${DST%/}"
    grep -q "^[^ ]* ${DST} " /proc/mounts 2>/dev/null
    return $?
}

montar_bind() {
    SRC="$1"
    DST="$2"

    # Crear destino si no existe
    if [ ! -d "$DST" ]; then
        mkdir -p "$DST"
        chown root:root "$DST"
        chmod 755 "$DST"
    fi

    # FIX 2: Verificar con /proc/mounts (confiable en Alpine/BusyBox)
    if esta_montado "$DST"; then
        print_info "  Bind mount ya existe: $DST"
        return 0
    fi

    # Montar
    if ! mount --bind "$SRC" "$DST"; then
        print_error "  Error al montar bind: $SRC -> $DST"
        return 1
    fi

    # Verificar que realmente quedo montado
    if ! esta_montado "$DST"; then
        print_error "  Mount ejecutado pero no aparece en /proc/mounts: $DST"
        return 1
    fi

    # Persistir en fstab eliminando entrada vieja si existe
    sed -i "\|${DST}|d" /etc/fstab 2>/dev/null || true
    echo "${SRC}  ${DST}  none  bind  0  0" >> /etc/fstab

    print_ok "  Bind mount: $DST -> $SRC"
    return 0
}

desmontar_bind() {
    DST="$1"
    DST="${DST%/}"

    # Eliminar entrada de fstab primero
    sed -i "\|${DST}|d" /etc/fstab 2>/dev/null || true

    # FIX 2: Verificar con /proc/mounts
    if esta_montado "$DST"; then
        umount "$DST" 2>/dev/null
        sleep 1
        # Si sigue montado, forzar con lazy unmount
        if esta_montado "$DST"; then
            umount -l "$DST" 2>/dev/null
            sleep 1
        fi
        print_ok "  Bind mount desmontado: $DST"
    fi

    # Eliminar el directorio vacio
    if [ -d "$DST" ] && ! esta_montado "$DST"; then
        rmdir "$DST" 2>/dev/null || rm -rf "$DST" 2>/dev/null || true
    fi
}

construir_jaula_usuario() {
    USUARIO="$1"
    GRUPO="$2"
    print_info "Construyendo jaula FTP para '$USUARIO'..."
    JAULA="$USERS_ROOT/$USUARIO"
    PERSONAL="$JAULA/$USUARIO"
    mkdir -p "$JAULA"
    chown root:root "$JAULA"
    chmod 755 "$JAULA"
    mkdir -p "$PERSONAL"
    chown "${USUARIO}:${USUARIO}" "$PERSONAL"
    chmod 755 "$PERSONAL"
    # ACLs recursivas: el usuario puede crear subcarpetas a cualquier profundidad
    find "$PERSONAL" -type d -exec setfacl -m "u:${USUARIO}:rwx" -m "d:u:${USUARIO}:rwx" {} \; 2>/dev/null
    find "$PERSONAL" -type f -exec setfacl -m "u:${USUARIO}:rw"  {} \; 2>/dev/null
    print_ok "  Carpeta personal: $PERSONAL (permisos recursivos aplicados)"
    montar_bind "$GENERAL_DIR" "$JAULA/general"
    montar_bind "$FTP_ROOT/$GRUPO" "$JAULA/$GRUPO"
    print_ok "Jaula lista para '$USUARIO'."
}

destruir_jaula_usuario() {
    USUARIO="$1"
    JAULA="$USERS_ROOT/$USUARIO"
    print_info "Eliminando jaula de '$USUARIO'..."
    desmontar_bind "$JAULA/general"
    desmontar_bind "$JAULA/$GRUPO_REPROBADOS"
    desmontar_bind "$JAULA/$GRUPO_RECURSADORES"
    if [ -d "$JAULA" ]; then
        rm -rf "$JAULA"
        print_ok "  Carpeta home eliminada."
    fi
}

validar_usuario() {
    USUARIO="$1"
    if [ -z "$USUARIO" ]; then
        print_error "El nombre no puede estar vacio."; return 1
    fi
    if [ ${#USUARIO} -lt 3 ] || [ ${#USUARIO} -gt 20 ]; then
        print_error "El nombre debe tener entre 3 y 20 caracteres."; return 1
    fi
    if ! echo "$USUARIO" | grep -qE '^[a-zA-Z][a-zA-Z0-9_-]*$'; then
        print_error "Solo letras, numeros, - y _. Debe iniciar con letra."; return 1
    fi
    if getent passwd "$USUARIO" > /dev/null 2>&1; then
        print_error "El usuario '$USUARIO' ya existe."; return 1
    fi
    return 0
}

crear_usuario_ftp() {
    USUARIO="$1"
    PASSWORD="$2"
    GRUPO="$3"
    print_info "Creando usuario '$USUARIO' en grupo '$GRUPO'..."
    adduser -D \
            -G "$GRUPO_FTP" \
            -s /sbin/nologin \
            -h "$USERS_ROOT/$USUARIO" \
            -g "Usuario FTP - $GRUPO" \
            "$USUARIO" 2>/dev/null
    if [ $? -ne 0 ]; then
        print_error "Error al crear usuario '$USUARIO'."
        return 1
    fi
    printf '%s\n%s\n' "$PASSWORD" "$PASSWORD" | passwd "$USUARIO" > /dev/null 2>&1
    print_ok "Usuario del sistema creado."
    adduser "$USUARIO" "$GRUPO_FTP" 2>/dev/null
    if [ "$GRUPO" = "$GRUPO_REPROBADOS" ]; then
        delgroup "$USUARIO" "$GRUPO_RECURSADORES" 2>/dev/null || true
        adduser "$USUARIO" "$GRUPO_REPROBADOS"
    else
        delgroup "$USUARIO" "$GRUPO_REPROBADOS" 2>/dev/null || true
        adduser "$USUARIO" "$GRUPO_RECURSADORES"
    fi
    print_ok "Usuario agregado al grupo '$GRUPO'."
    construir_jaula_usuario "$USUARIO" "$GRUPO"
    printf "\n"
    printf "${C_GREEN}[OK]    ═══════════════════════════════════════════${C_RESET}\n"
    printf "${C_GREEN}[OK]      Usuario '%s' creado correctamente${C_RESET}\n" "$USUARIO"
    printf "${C_GREEN}[OK]    ═══════════════════════════════════════════${C_RESET}\n"
    printf "${C_CYAN}[INFO]    Estructura al conectar por FTP:${C_RESET}\n"
    printf "${C_CYAN}[INFO]      /general/      (publica, todos leen y escriben)${C_RESET}\n"
    printf "${C_CYAN}[INFO]      /%s/       (solo tu grupo)${C_RESET}\n" "$GRUPO"
    printf "${C_CYAN}[INFO]      /%s/     (personal)${C_RESET}\n" "$USUARIO"
    printf "${C_GREEN}[OK]    ═══════════════════════════════════════════${C_RESET}\n"
    return 0
}

cambiar_grupo_usuario() {
    USUARIO="$1"

    if ! getent passwd "$USUARIO" > /dev/null 2>&1; then
        print_error "El usuario '$USUARIO' no existe."
        return
    fi

    # Detectar grupo actual
    GRUPO_ACTUAL=""
    if id -nG "$USUARIO" | grep -qw "$GRUPO_REPROBADOS"; then
        GRUPO_ACTUAL="$GRUPO_REPROBADOS"
    elif id -nG "$USUARIO" | grep -qw "$GRUPO_RECURSADORES"; then
        GRUPO_ACTUAL="$GRUPO_RECURSADORES"
    fi

    print_info "Grupo actual de '$USUARIO': ${GRUPO_ACTUAL:-'(ninguno)'}"

    printf "\n"
    printf "  Nuevo grupo:\n"
    printf "  1) %s\n" "$GRUPO_REPROBADOS"
    printf "  2) %s\n" "$GRUPO_RECURSADORES"
    printf "Seleccione [1-2]: "
    read OPCION

    case "$OPCION" in
        1) NUEVO_GRUPO="$GRUPO_REPROBADOS" ;;
        2) NUEVO_GRUPO="$GRUPO_RECURSADORES" ;;
        *) print_error "Opcion invalida."; return ;;
    esac

    if [ "$GRUPO_ACTUAL" = "$NUEVO_GRUPO" ]; then
        print_info "El usuario ya pertenece a '$NUEVO_GRUPO'."
        return
    fi

    print_info "Cambiando '$USUARIO': '$GRUPO_ACTUAL' -> '$NUEVO_GRUPO'..."

    JAULA="$USERS_ROOT/$USUARIO"

    # Si la jaula no existe, reconstruirla desde cero
    if [ ! -d "$JAULA" ]; then
        print_warn "Jaula no encontrada, reconstruyendo desde cero..."
        mkdir -p "$JAULA"
        chown root:root "$JAULA"
        chmod 755 "$JAULA"
        mkdir -p "$JAULA/$USUARIO"
        chown "${USUARIO}:${USUARIO}" "$JAULA/$USUARIO"
        chmod 755 "$JAULA/$USUARIO"
        montar_bind "$GENERAL_DIR" "$JAULA/general"
    fi

    # Detener vsftpd ANTES de tocar bind mounts
    print_warn "Deteniendo vsftpd para liberar bind mounts..."
    rc-service vsftpd stop > /dev/null 2>&1
    sleep 2

    # Desmontar AMBOS grupos para limpiar cualquier estado inconsistente
    desmontar_bind "$JAULA/$GRUPO_REPROBADOS"
    desmontar_bind "$JAULA/$GRUPO_RECURSADORES"

    # Cambiar grupo del sistema
    if [ -n "$GRUPO_ACTUAL" ]; then
        delgroup "$USUARIO" "$GRUPO_ACTUAL" 2>/dev/null || true
        print_ok "Removido de '$GRUPO_ACTUAL'."
    fi
    adduser "$USUARIO" "$NUEVO_GRUPO" > /dev/null 2>&1
    print_ok "Agregado a '$NUEVO_GRUPO'."

    # Re-aplicar permisos en la carpeta real del grupo destino
    chown root:"$NUEVO_GRUPO" "$FTP_ROOT/$NUEVO_GRUPO"
    chmod 3770 "$FTP_ROOT/$NUEVO_GRUPO"
    aplicar_permisos_recursivos "$FTP_ROOT/$NUEVO_GRUPO" "$NUEVO_GRUPO"
    print_ok "Permisos verificados en '$FTP_ROOT/$NUEVO_GRUPO'."

    # Crear bind mount del nuevo grupo con verificacion via /proc/mounts
    if montar_bind "$FTP_ROOT/$NUEVO_GRUPO" "$JAULA/$NUEVO_GRUPO"; then
        print_ok "Bind mount '$NUEVO_GRUPO' creado correctamente."
    else
        print_error "Error al crear bind mount. Verifica que corres el script como root."
    fi

    # Garantizar permisos correctos de la jaula (vsftpd exige root:root 755)
    chown root:root "$JAULA"
    chmod 755 "$JAULA"

    # FIX 1: Asegurarse de que seccomp_sandbox=NO sigue en el conf
    # antes de arrancar vsftpd para evitar que se caiga silenciosamente
    if ! grep -q "seccomp_sandbox=NO" "$VSFTPD_CONF" 2>/dev/null; then
        echo "seccomp_sandbox=NO" >> "$VSFTPD_CONF"
        print_warn "seccomp_sandbox=NO re-agregado al config."
    fi

    # Arrancar vsftpd de nuevo
    rc-service vsftpd start > /dev/null 2>&1
    sleep 1

    # Verificar que arranco correctamente
    if rc-service vsftpd status > /dev/null 2>&1; then
        print_ok "Servicio vsftpd reiniciado correctamente."
    else
        print_error "vsftpd no arranco. Revisa: tail -20 /var/log/vsftpd.log"
    fi

    print_ok "Usuario '$USUARIO' movido a '$NUEVO_GRUPO'."
    print_info "Nueva estructura FTP:"
    print_info "  /general/         (publica)"
    print_info "  /$NUEVO_GRUPO/    (nuevo grupo)"
    print_info "  /$USUARIO/        (personal)"
    print_warn "El usuario debe reconectarse en FileZilla."
}

instalar_ftp() {
    print_titulo "Instalacion y Configuracion de Servidor FTP"
    if verificar_instalacion; then
        printf "vsftpd ya instalado. Reconfigurar? [s/N]: "
        read RECONF
        if ! echo "$RECONF" | grep -qiE '^s$'; then
            print_info "Cancelado."
            return
        fi
    else
        print_info "Instalando vsftpd y acl..."
        apk update > /dev/null 2>&1
        apk add vsftpd acl > /dev/null 2>&1
        if command -v vsftpd > /dev/null 2>&1; then
            print_ok "vsftpd instalado."
        else
            print_error "Error en la instalacion de vsftpd."
            return
        fi
    fi
    crear_grupos
    crear_estructura_base
    configurar_vsftpd
    configurar_firewall
    rc-update add vsftpd default 2>/dev/null
    rc-service vsftpd restart
    IP=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d/ -f1)
    printf "\n"
    printf "${C_GREEN}[OK]    ══════════════════════════════════════════════${C_RESET}\n"
    printf "${C_GREEN}[OK]      Servidor FTP listo${C_RESET}\n"
    printf "${C_GREEN}[OK]    ══════════════════════════════════════════════${C_RESET}\n"
    printf "${C_CYAN}[INFO]    IP     : %s${C_RESET}\n" "$IP"
    printf "${C_CYAN}[INFO]    Puerto : 21${C_RESET}\n"
    printf "${C_CYAN}[INFO]    Anon   : ftp://%s  (solo lectura en /general)${C_RESET}\n" "$IP"
    printf "${C_GREEN}[OK]    ══════════════════════════════════════════════${C_RESET}\n"
    print_info "Cree usuarios con: ./ftp_server.sh -users"
}

listar_usuarios_ftp() {
    print_titulo "Usuarios FTP Configurados"
    ENCONTRADOS=0
    printf "${C_BOLD}%-20s %-15s %-10s${C_RESET}\n" "Usuario" "Grupo" "Jaula"
    printf "%-20s %-15s %-10s\n" "-------" "-----" "-----"
    for GRUPO in "$GRUPO_REPROBADOS" "$GRUPO_RECURSADORES"; do
        MIEMBROS=$(getent group "$GRUPO" | cut -d: -f4 | tr ',' '\n' | grep -v '^$')
        for USUARIO in $MIEMBROS; do
            if [ -d "$USERS_ROOT/$USUARIO" ]; then
                JAULA_OK="${C_GREEN}OK${C_RESET}"
            else
                JAULA_OK="${C_RED}FALTA${C_RESET}"
            fi
            printf "%-20s %-15s " "$USUARIO" "$GRUPO"
            printf "${JAULA_OK}\n"
            ENCONTRADOS=$((ENCONTRADOS + 1))
        done
    done
    if [ "$ENCONTRADOS" -eq 0 ]; then
        print_info "No hay usuarios FTP configurados."
    fi
}

gestionar_usuarios() {
    print_titulo "Gestion de Usuarios FTP"
    if ! verificar_instalacion; then
        print_error "vsftpd no instalado. Ejecute: ./ftp_server.sh -install"
        return
    fi
    printf "  1) Crear nuevos usuarios\n"
    printf "  2) Cambiar grupo de un usuario\n"
    printf "  3) Eliminar usuario\n"
    printf "  4) Cambiar contrasena de usuario\n"
    printf "  5) Volver\n\n"
    printf "Seleccione [1-5]: "
    read OPCION
    case "$OPCION" in
        1)
            printf "Cuantos usuarios desea crear?: "
            read NUM
            if ! echo "$NUM" | grep -qE '^[0-9]+$' || [ "$NUM" -lt 1 ]; then
                print_error "Numero invalido."; return
            fi
            i=1
            while [ "$i" -le "$NUM" ]; do
                printf "\n"
                print_titulo "Usuario $i de $NUM"
                USUARIO=""
                while ! validar_usuario "$USUARIO" 2>/dev/null || [ -z "$USUARIO" ]; do
                    printf "Nombre de usuario: "
                    read USUARIO
                    validar_usuario "$USUARIO" || USUARIO=""
                done
                PASSWORD=""
                while [ -z "$PASSWORD" ]; do
                    printf "Contrasena (min 8 caracteres, una mayuscula, un numero y un caracter especial): "
                    read PASSWORD
                done
                printf "  1) %s\n" "$GRUPO_REPROBADOS"
                printf "  2) %s\n" "$GRUPO_RECURSADORES"
                printf "Grupo [1-2]: "
                read GRUP_OP
                case "$GRUP_OP" in
                    1) GRUPO="$GRUPO_REPROBADOS" ;;
                    2) GRUPO="$GRUPO_RECURSADORES" ;;
                    *) print_warn "Opcion invalida, asignando a reprobados."
                       GRUPO="$GRUPO_REPROBADOS" ;;
                esac
                crear_usuario_ftp "$USUARIO" "$PASSWORD" "$GRUPO"
                i=$((i + 1))
            done
            ;;
        2)
            listar_usuarios_ftp
            printf "Usuario a cambiar de grupo: "
            read USUARIO
            cambiar_grupo_usuario "$USUARIO"
            ;;
        3)
            listar_usuarios_ftp
            printf "Usuario a eliminar: "
            read USUARIO
            if ! getent passwd "$USUARIO" > /dev/null 2>&1; then
                print_error "Usuario '$USUARIO' no existe."; return
            fi
            printf "Confirma eliminar '$USUARIO'? [s/N]: "
            read CONFIRMAR
            if echo "$CONFIRMAR" | grep -qiE '^s$'; then
                destruir_jaula_usuario "$USUARIO"
                deluser "$USUARIO" 2>/dev/null
                print_ok "Usuario '$USUARIO' eliminado."
            else
                print_info "Cancelado."
            fi
            ;;
        4)
            listar_usuarios_ftp
            printf "Nombre del usuario: "
            read USUARIO
            if ! getent passwd "$USUARIO" > /dev/null 2>&1; then
                print_error "Usuario '$USUARIO' no existe."; return
            fi
            printf "Nueva contrasena: "
            read NEW_PASS
            printf '%s\n%s\n' "$NEW_PASS" "$NEW_PASS" | passwd "$USUARIO" > /dev/null 2>&1
            print_ok "Contrasena de '$USUARIO' actualizada."
            ;;
        5) return ;;
        *) print_error "Opcion invalida." ;;
    esac
}

ver_estado() {
    print_titulo "ESTADO DEL SERVIDOR FTP"
    printf "  Servicio vsftpd : "
    if rc-service vsftpd status > /dev/null 2>&1; then
        printf "${C_GREEN}Running${C_RESET}\n"
    else
        printf "${C_RED}Stopped${C_RESET}\n"
    fi
    printf "  Puerto 21       : "
    if ss -tlnp 2>/dev/null | grep -q ':21 ' || netstat -tlnp 2>/dev/null | grep -q ':21 '; then
        printf "${C_GREEN}Escuchando${C_RESET}\n"
    else
        printf "${C_RED}No escuchando${C_RESET}\n"
    fi
    printf "\n"
    print_info "Conexiones activas en puerto 21:"
    ss -an 2>/dev/null | grep ':21 ' || netstat -an 2>/dev/null | grep ':21 '
    printf "\n"
    listar_usuarios_ftp
}

reiniciar_ftp() {
    print_info "Reiniciando servidor FTP..."
    rc-service vsftpd restart
    print_ok "Servidor FTP reiniciado."
}

mostrar_ayuda() {
    printf "\n"
    printf "${C_CYAN}Uso: ./ftp_server.sh [opcion]${C_RESET}\n\n"
    printf "  -install   Instala y configura el servidor FTP (primera vez)\n"
    printf "  -users     Gestionar usuarios (crear, cambiar grupo, eliminar)\n"
    printf "  -status    Ver estado del servidor y usuarios\n"
    printf "  -restart   Reiniciar el servicio FTP\n"
    printf "  -verify    Verificar si vsftpd esta instalado\n"
    printf "  -list      Listar usuarios y estructura\n"
    printf "  -help      Mostrar esta ayuda\n"
    printf "\n"
    printf "${C_YELLOW}Orden recomendado (primera vez):${C_RESET}\n"
    printf "  1. ./ftp_server.sh -install\n"
    printf "  2. ./ftp_server.sh -users\n\n"
}

case "$1" in
    -verify)  verificar_instalacion ;;
    -install) instalar_ftp ;;
    -users)   gestionar_usuarios ;;
    -restart) reiniciar_ftp ;;
    -status)  ver_estado ;;
    -list)    listar_usuarios_ftp ;;
    -help)    mostrar_ayuda ;;
    *)        mostrar_ayuda ;;
esac