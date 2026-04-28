# =============================================================================
# Dockerfile — Servidor Web Nginx personalizado
# Base: Alpine Linux (imagen ligera)
# Seguridad:
#   - Server tokens desactivados (no expone versión de Nginx)
#   - Proceso ejecutado con usuario no-root (webuser)
# =============================================================================

FROM alpine:3.19

# Instalar Nginx
RUN apk add --no-cache nginx

# Crear usuario no-root para ejecutar Nginx
RUN addgroup -S webgroup && adduser -S webuser -G webgroup

# Copiar configuración personalizada
COPY nginx.conf /etc/nginx/nginx.conf

# Copiar contenido web
COPY html/ /var/www/html/

# Crear directorios necesarios y ajustar permisos
RUN mkdir -p /var/log/nginx /var/lib/nginx/tmp /run/nginx \
    && chown -R webuser:webgroup /var/www/html \
                                 /var/log/nginx \
                                 /var/lib/nginx \
                                 /run/nginx \
    && chmod -R 755 /var/www/html

# Puerto 8080 (no-root no puede usar 80)
EXPOSE 8080

# Ejecutar como usuario no-root
USER webuser

CMD ["nginx", "-g", "daemon off;"]
