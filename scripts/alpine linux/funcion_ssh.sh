#!/bin/sh
# ==============================================================================
# ssh_functions.sh
# Librería de funciones para la gestión del servicio OpenSSH en Alpine Linux
# ==============================================================================

verificar_ssh() {
    echo ""
    echo "--- Verificando estado de OpenSSH Server ---"

    if rc-service sshd status > /dev/null 2>&1; then
        echo "[OK] El servicio sshd está ACTIVO."
    else
        echo "[!!] El servicio sshd está INACTIVO o no instalado."
    fi

    if rc-update show default 2>/dev/null | grep -q "sshd"; then
        echo "[OK] sshd está configurado para iniciar en el BOOT."
    else
        echo "[!!] sshd NO está en el arranque automático."
    fi

    if [ -f /etc/ssh/sshd_config ]; then
        echo "[OK] Archivo de configuración encontrado: /etc/ssh/sshd_config"
        PUERTO=$(grep "^Port " /etc/ssh/sshd_config | awk '{print $2}')
        if [ -n "$PUERTO" ]; then
            echo "     Puerto configurado: $PUERTO"
        else
            echo "     Puerto por defecto: 22"
        fi
    else
        echo "[!!] Archivo sshd_config no encontrado."
    fi
}

# ------------------------------------------------------------------------------

instalar_ssh() {
    echo ""
    echo "--- Instalación de OpenSSH Server ---"

    # Verificar si ya está instalado
    if apk info openssh-server > /dev/null 2>&1; then
        echo "[OK] OpenSSH Server ya está instalado."
    else
        echo "Instalando openssh-server..."
        apk add --no-cache openssh-server
        if [ $? -ne 0 ]; then
            echo "[ERROR] Falló la instalación. Verifica tu conexión de red."
            return 1
        fi
        echo "[OK] openssh-server instalado correctamente."
    fi

    # Generar claves del host si no existen
    if [ ! -f /etc/ssh/ssh_host_rsa_key ]; then
        echo "Generando claves del servidor SSH..."
        ssh-keygen -A
        echo "[OK] Claves generadas."
    fi

    # Habilitar inicio en el boot
    echo "Habilitando inicio automático en el boot..."
    rc-update add sshd default
    echo "[OK] sshd añadido al arranque."

    # Iniciar el servicio ahora
    echo "Iniciando el servicio sshd..."
    rc-service sshd start
    if [ $? -eq 0 ]; then
        echo "[OK] Servicio sshd iniciado."
    else
        echo "[ERROR] No se pudo iniciar el servicio."
        return 1
    fi

    # Mostrar IP para conectarse
    IP=$(ip addr show eth0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
    if [ -z "$IP" ]; then
        IP=$(hostname -I | awk '{print $1}')
    fi
    echo ""
    echo "✔ SSH listo. Desde el cliente conéctate con:"
    echo "  ssh root@$IP"
    echo "  (o el usuario que corresponda)"
}

# ------------------------------------------------------------------------------

desinstalar_ssh() {
    echo ""
    echo "--- Desinstalación de OpenSSH Server ---"

    if ! apk info openssh-server > /dev/null 2>&1; then
        echo "[INFO] openssh-server no está instalado. Nada que hacer."
        return 0
    fi

    echo "Deteniendo el servicio sshd..."
    rc-service sshd stop 2>/dev/null

    echo "Eliminando del arranque automático..."
    rc-update del sshd default 2>/dev/null

    echo "Desinstalando openssh-server..."
    apk del openssh-server
    if [ $? -eq 0 ]; then
        echo "[OK] openssh-server desinstalado correctamente."
    else
        echo "[ERROR] No se pudo desinstalar."
    fi
}

# ------------------------------------------------------------------------------

menu_ssh() {
    echo ""
    echo "========================================"
    echo "      GESTIÓN DE SERVICIO SSH           "
    echo "========================================"
    echo "1. Verificar estado de SSH"
    echo "2. Instalar y configurar SSH"
    echo "3. Desinstalar SSH"
    echo "4. Volver al menú principal"
    printf "Elige una opción: "
    read op

    case "$op" in
        1) verificar_ssh ;;
        2) instalar_ssh ;;
        3) desinstalar_ssh ;;
        4) return ;;
        *) echo "[ERROR] Opción inválida." ;;
    esac
}