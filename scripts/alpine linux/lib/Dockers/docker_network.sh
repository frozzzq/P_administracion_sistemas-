#!/bin/sh
# docker_network.sh - Red personalizada infra_red

crear_red() {
    print_info "[INFO] Verificando red infra_red..."

    if docker network ls --format '{{.Name}}' | grep -q "^infra_red$"; then
        print_completado "[OK] Red infra_red ya existe"
    else
        print_info "[INFO] Creando red infra_red (172.20.0.0/16)..."
        docker network create \
            --driver bridge \
            --subnet 172.20.0.0/16 \
            infra_red >/dev/null 2>&1

        if [ $? -eq 0 ]; then
            print_completado "[OK] Red infra_red creada correctamente"
        else
            print_error "[ERROR] No se pudo crear la red infra_red"
            exit 1
        fi
    fi
}

eliminar_red() {
    print_info "[INFO] Eliminando red infra_red..."

    if docker network ls --format '{{.Name}}' | grep -q "^infra_red$"; then
        docker network rm infra_red >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            print_completado "[OK] Red infra_red eliminada"
        else
            print_error "[ERROR] No se pudo eliminar la red (puede tener contenedores activos)"
        fi
    else
        print_info "[INFO] La red infra_red no existe, nada que eliminar"
    fi
}
