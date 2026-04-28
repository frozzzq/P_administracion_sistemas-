#!/bin/sh
# docker_ftp.sh - Servidor FTP con Alpine FTP Server
# En Alpine Linux, las interfaces de red suelen llamarse eth0, eth1, eth2
# El adaptador puente (internet) generalmente es eth2 en la config de 3 adaptadores

obtener_ip_puente() {
    # Intenta detectar la IP del adaptador con gateway (internet)
    ip route | awk '/default/ {print $5}' | head -1 | xargs -I{} ip -4 addr show {} | awk '/inet /{split($2,a,"/"); print a[1]; exit}'
}

iniciar_ftp() {
    print_info "[INFO] Verificando contenedor ftp_server..."

    if docker ps --format '{{.Names}}' | grep -q "^ftp_server$"; then
        print_completado "[OK] Contenedor ftp_server ya esta corriendo"
        return
    fi

    # Detectar IP del adaptador puente automaticamente
    IP_PUENTE=$(obtener_ip_puente)
    if [ -z "$IP_PUENTE" ]; then
        print_error "[ERROR] No se pudo detectar la IP del adaptador puente"
        IP_PUENTE="0.0.0.0"
    fi
    print_info "[INFO] IP del adaptador detectada: $IP_PUENTE"

    if docker ps -a --format '{{.Names}}' | grep -q "^ftp_server$"; then
        print_info "[INFO] Contenedor ftp_server detenido, iniciando..."
        docker start ftp_server >/dev/null 2>&1
    else
        print_info "[INFO] Creando contenedor ftp_server..."
        docker run -d \
            --name ftp_server \
            --network infra_red \
            --volume web_content:/ftp/$FTP_USER \
            --memory 512m \
            --cpus 0.5 \
            --restart always \
            -p 21:21 \
            -p 21000-21010:21000-21010 \
            -e USERS="$FTP_USER|$FTP_PASS|/ftp/$FTP_USER" \
            -e ADDRESS="$IP_PUENTE" \
            -e MIN_PORT=21000 \
            -e MAX_PORT=21010 \
            delfer/alpine-ftp-server >/dev/null 2>&1
    fi

    if [ $? -eq 0 ]; then
        print_completado "[OK] Contenedor ftp_server iniciado"
    else
        print_error "[ERROR] No se pudo iniciar el contenedor ftp_server"
        exit 1
    fi
}

detener_ftp() {
    print_info "[INFO] Deteniendo contenedor ftp_server..."

    if docker ps --format '{{.Names}}' | grep -q "^ftp_server$"; then
        docker stop ftp_server >/dev/null 2>&1
        print_completado "[OK] Contenedor ftp_server detenido"
    else
        print_info "[INFO] Contenedor ftp_server no esta corriendo"
    fi
}

eliminar_ftp() {
    detener_ftp
    if docker ps -a --format '{{.Names}}' | grep -q "^ftp_server$"; then
        docker rm ftp_server >/dev/null 2>&1
        print_completado "[OK] Contenedor ftp_server eliminado"
    fi
}
