#!/bin/sh
# practica10.sh - Infraestructura Docker en Alpine Linux
# Uso: ./practica10.sh [-i|-v|-s|-u|-b|-r|-h]

MAIN_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$MAIN_DIR/../lib"
FUNCIONES="$LIB_DIR/Dockers"

. "$MAIN_DIR/claves.txt"
. "$LIB_DIR/utils.sh"
. "$FUNCIONES/docker_install.sh"
. "$FUNCIONES/docker_network.sh"
. "$FUNCIONES/docker_volumenes.sh"
. "$FUNCIONES/docker_web.sh"
. "$FUNCIONES/docker_db.sh"
. "$FUNCIONES/docker_ftp.sh"

instalar() {
    print_titulo "Instalacion completa"
    instalar_docker
    crear_red
    crear_volumenes
    construir_imagen_web
    iniciar_web
    iniciar_db
    iniciar_ftp
    print_titulo "Instalacion finalizada"
    verificar
}

verificar() {
    print_titulo "Estado de contenedores"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
    print_titulo "Uso de recursos"
    docker stats --no-stream
}

detener() {
    print_titulo "Deteniendo servicios"
    detener_ftp
    detener_web
    detener_db
    print_completado "[OK] Todos los servicios detenidos"
}

iniciar() {
    print_titulo "Iniciando servicios"
    iniciar_web
    iniciar_db
    iniciar_ftp
    print_completado "[OK] Todos los servicios iniciados"
}

resetear() {
    print_titulo "Reseteo completo"
    print_info "[INFO] Esto eliminara contenedores, red y volumenes"
    printf "  Estas seguro? (s/N): "
    read confirm
    if echo "$confirm" | grep -qiE "^s$"; then
        eliminar_ftp
        eliminar_web
        eliminar_db
        eliminar_red
        eliminar_volumenes
        print_completado "[OK] Reset completado"
    else
        print_info "[INFO] Operacion cancelada"
    fi
}

ayuda() {
    print_titulo "Practica 10 - Infraestructura con Docker"
    echo -e "  ${verde}-i${nc}   Instalar y levantar todos los servicios"
    echo -e "  ${verde}-v${nc}   Verificar estado de contenedores y recursos"
    echo -e "  ${verde}-s${nc}   Detener todos los contenedores"
    echo -e "  ${verde}-u${nc}   Iniciar contenedores detenidos"
    echo -e "  ${verde}-b${nc}   Generar respaldo manual de la base de datos"
    echo -e "  ${verde}-r${nc}   Resetear todo (elimina contenedores y volumenes)"
    echo -e "  ${verde}-h${nc}   Mostrar esta ayuda"
    echo ""
}

if [ $# -eq 0 ]; then
    ayuda
    exit 0
fi

while getopts "ivsubhr" opt; do
    case $opt in
        i) instalar ;;
        v) verificar ;;
        s) detener ;;
        u) iniciar ;;
        b) hacer_backup_db ;;
        r) resetear ;;
        h) ayuda ;;
        *) print_error "[ERROR] Opcion invalida. Usa -h para ver la ayuda" ; exit 1 ;;
    esac
done
