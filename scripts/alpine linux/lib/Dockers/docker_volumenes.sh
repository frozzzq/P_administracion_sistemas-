#!/bin/sh
# docker_volumenes.sh - Volumenes persistentes

crear_volumenes() {
    print_info "[INFO] Verificando volumenes..."

    if docker volume ls --format '{{.Name}}' | grep -q "^db_data$"; then
        print_completado "[OK] Volumen db_data ya existe"
    else
        docker volume create db_data >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            print_completado "[OK] Volumen db_data creado"
        else
            print_error "[ERROR] No se pudo crear el volumen db_data"
            exit 1
        fi
    fi

    if docker volume ls --format '{{.Name}}' | grep -q "^web_content$"; then
        print_completado "[OK] Volumen web_content ya existe"
    else
        docker volume create web_content >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            print_completado "[OK] Volumen web_content creado"
        else
            print_error "[ERROR] No se pudo crear el volumen web_content"
            exit 1
        fi
    fi
}

eliminar_volumenes() {
    print_info "[INFO] Eliminando volumenes..."

    for vol in db_data web_content; do
        if docker volume ls --format '{{.Name}}' | grep -q "^${vol}$"; then
            docker volume rm "$vol" >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                print_completado "[OK] Volumen $vol eliminado"
            else
                print_error "[ERROR] No se pudo eliminar el volumen $vol"
            fi
        else
            print_info "[INFO] Volumen $vol no existe, nada que eliminar"
        fi
    done
}
