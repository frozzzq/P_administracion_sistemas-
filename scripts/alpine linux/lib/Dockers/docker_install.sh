#!/bin/sh
# docker_install.sh - Instalacion de Docker en Alpine Linux

verificar_docker() {
    print_info "[INFO] Verificando instalacion de Docker..."
    if command -v docker >/dev/null 2>&1; then
        print_completado "[OK] Docker ya esta instalado: $(docker --version)"
    else
        print_info "[INFO] Docker no encontrado, instalando..."
        apk add --no-cache docker docker-cli >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            print_completado "[OK] Docker instalado correctamente"
        else
            print_error "[ERROR] Fallo la instalacion de Docker"
            exit 1
        fi
    fi
}

verificar_cron() {
    print_info "[INFO] Verificando cron..."
    if command -v crontab >/dev/null 2>&1; then
        print_completado "[OK] Cron ya esta instalado"
        return
    fi
    print_info "[INFO] Instalando dcron..."
    apk add --no-cache dcron >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        rc-update add dcron default >/dev/null 2>&1
        rc-service dcron start >/dev/null 2>&1
        print_completado "[OK] dcron instalado y activo"
    else
        print_error "[ERROR] No se pudo instalar dcron"
    fi
}

verificar_servicio_docker() {
    print_info "[INFO] Verificando servicio Docker..."
    if rc-service docker status 2>/dev/null | grep -q "started"; then
        print_completado "[OK] Servicio Docker activo"
    else
        print_info "[INFO] Iniciando servicio Docker..."
        rc-update add docker default >/dev/null 2>&1
        rc-service docker start >/dev/null 2>&1
        if rc-service docker status 2>/dev/null | grep -q "started"; then
            print_completado "[OK] Servicio Docker iniciado"
        else
            print_error "[ERROR] No se pudo iniciar Docker"
            exit 1
        fi
    fi
}

verificar_grupo_docker() {
    print_info "[INFO] Verificando grupo docker..."
    if id | grep -q "docker"; then
        print_completado "[OK] Usuario ya pertenece al grupo docker"
    else
        addgroup "$USER" docker >/dev/null 2>&1
        print_info "[INFO] Usuario agregado al grupo docker"
        print_error "[AVISO] Cierra sesion y vuelve a entrar, o ejecuta: newgrp docker"
        exit 0
    fi
}

abrir_puertos_firewall() {
    print_info "[INFO] Configurando firewall con iptables..."
    if command -v iptables >/dev/null 2>&1; then
        iptables -I INPUT -p tcp --dport 8080 -j ACCEPT >/dev/null 2>&1
        iptables -I INPUT -p tcp --dport 21   -j ACCEPT >/dev/null 2>&1
        iptables -I INPUT -p tcp --dport 21000:21010 -j ACCEPT >/dev/null 2>&1
        print_completado "[OK] Puertos abiertos: 8080, 21, 21000-21010"
    else
        print_info "[INFO] iptables no disponible, omitiendo firewall"
    fi
}

instalar_docker() {
    verificar_docker
    verificar_cron
    verificar_servicio_docker
    verificar_grupo_docker
    abrir_puertos_firewall
}
