#!/bin/sh
# docker_db.sh - Contenedor PostgreSQL con respaldo automatico

BACKUP_DIR="/opt/docker_backups"

iniciar_db() {
    print_info "[INFO] Verificando contenedor db_server..."

    if docker ps --format '{{.Names}}' | grep -q "^db_server$"; then
        print_completado "[OK] Contenedor db_server ya esta corriendo"
        return
    fi

    if docker ps -a --format '{{.Names}}' | grep -q "^db_server$"; then
        print_info "[INFO] Contenedor db_server detenido, iniciando..."
        docker start db_server >/dev/null 2>&1
    else
        print_info "[INFO] Creando contenedor db_server..."
        docker run -d \
            --name db_server \
            --network infra_red \
            --volume db_data:/var/lib/postgresql/data \
            --memory 512m \
            --cpus 0.5 \
            --restart always \
            -e POSTGRES_USER="$PG_USER" \
            -e POSTGRES_PASSWORD="$PG_PASS" \
            -e POSTGRES_DB="$PG_DB" \
            postgres:16-alpine >/dev/null 2>&1
    fi

    if [ $? -eq 0 ]; then
        print_completado "[OK] Contenedor db_server iniciado"
        configurar_backup_db
    else
        print_error "[ERROR] No se pudo iniciar el contenedor db_server"
        exit 1
    fi
}

configurar_backup_db() {
    print_info "[INFO] Configurando respaldo automatico de PostgreSQL..."

    install -d -m 750 "$BACKUP_DIR" >/dev/null 2>&1

    BACKUP_SCRIPT="/usr/local/bin/backup_db.sh"
    cat > "$BACKUP_SCRIPT" << EOF
#!/bin/sh
FECHA=\$(date +%Y%m%d_%H%M%S)
docker exec db_server pg_dump -U $PG_USER $PG_DB > "$BACKUP_DIR/backup_\$FECHA.sql" 2>/dev/null
ls -t "$BACKUP_DIR"/backup_*.sql 2>/dev/null | tail -n +8 | xargs rm -f
EOF
    chmod +x "$BACKUP_SCRIPT"

    # Cron diario a las 2:00 AM con dcron (Alpine), evita duplicados
    ( crontab -l 2>/dev/null | grep -v backup_db; echo "0 2 * * * $BACKUP_SCRIPT" ) | crontab 

    print_completado "[OK] Respaldo automatico configurado (diario a las 2:00 AM)"
    print_info "[INFO] Respaldos en: $BACKUP_DIR"
}

hacer_backup_db() {
    print_info "[INFO] Ejecutando respaldo manual de PostgreSQL..."
    install -d -m 750 "$BACKUP_DIR" >/dev/null 2>&1
    FECHA=$(date +%Y%m%d_%H%M%S)
    if docker exec db_server pg_dump -U "$PG_USER" "$PG_DB" > "$BACKUP_DIR/backup_$FECHA.sql" 2>/dev/null; then
        print_completado "[OK] Respaldo guardado: $BACKUP_DIR/backup_$FECHA.sql"
    else
        print_error "[ERROR] No se pudo generar el respaldo"
    fi
}

detener_db() {
    print_info "[INFO] Deteniendo contenedor db_server..."

    if docker ps --format '{{.Names}}' | grep -q "^db_server$"; then
        docker stop db_server >/dev/null 2>&1
        print_completado "[OK] Contenedor db_server detenido"
    else
        print_info "[INFO] Contenedor db_server no esta corriendo"
    fi
}

eliminar_db() {
    detener_db
    if docker ps -a --format '{{.Names}}' | grep -q "^db_server$"; then
        docker rm db_server >/dev/null 2>&1
        print_completado "[OK] Contenedor db_server eliminado"
    fi
}
