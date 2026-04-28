#!/bin/sh
# docker_web.sh - Servidor web Nginx personalizado
WEB_DIR="$MAIN_DIR/web"
DOCKERFILE="$MAIN_DIR/Dockerfile"
construir_imagen_web() {
    print_info "[INFO] Verificando imagen web_server_img..."

    if docker image ls --format '{{.Repository}}' | grep -q "^web_server_img$"; then
        print_completado "[OK] Imagen web_server_img ya existe"
    else
        print_info "[INFO] Construyendo imagen web_server_img..."
        docker build -f "$DOCKERFILE" -t web_server_img "$WEB_DIR" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            print_completado "[OK] Imagen web_server_img construida"
        else
            print_error "[ERROR] No se pudo construir la imagen web_server_img"
            exit 1
        fi
    fi
}

iniciar_web() {
    print_info "[INFO] Verificando contenedor web_server..."

    if docker ps --format '{{.Names}}' | grep -q "^web_server$"; then
        print_completado "[OK] Contenedor web_server ya esta corriendo"
        return
    fi

    if docker ps -a --format '{{.Names}}' | grep -q "^web_server$"; then
        print_info "[INFO] Contenedor web_server detenido, iniciando..."
        docker start web_server >/dev/null 2>&1
    else
        print_info "[INFO] Creando contenedor web_server..."
        docker run -d \
            --name web_server \
            --network infra_red \
            --volume web_content:/usr/share/nginx/html \
            --memory 512m \
            --cpus 0.5 \
            --restart always \
            -p 8080:80 \
            web_server_img >/dev/null 2>&1
    fi

    if [ $? -eq 0 ]; then
        print_completado "[OK] Contenedor web_server iniciado"
    else
        print_error "[ERROR] No se pudo iniciar el contenedor web_server"
        exit 1
    fi
}

detener_web() {
    print_info "[INFO] Deteniendo contenedor web_server..."

    if docker ps --format '{{.Names}}' | grep -q "^web_server$"; then
        docker stop web_server >/dev/null 2>&1
        print_completado "[OK] Contenedor web_server detenido"
    else
        print_info "[INFO] Contenedor web_server no esta corriendo"
    fi
}

eliminar_web() {
    detener_web
    if docker ps -a --format '{{.Names}}' | grep -q "^web_server$"; then
        docker rm web_server >/dev/null 2>&1
        print_completado "[OK] Contenedor web_server eliminado"
    fi
}
