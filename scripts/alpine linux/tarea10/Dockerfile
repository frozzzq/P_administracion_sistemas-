FROM nginx:alpine

# Crear usuario sin privilegios para ejecutar workers
RUN adduser -D -H -s /sbin/nologin webuser

# Desactivar server tokens (oculta version de Nginx)
RUN sed -i '/^http {/a\    server_tokens off;' /etc/nginx/nginx.conf

# Cambiar el usuario de los workers a webuser
# (el proceso master sigue en root para bindear el puerto 80)
RUN sed -i 's/^user .*/user  webuser;/' /etc/nginx/nginx.conf

# Copiar contenido web con permisos del usuario webuser
COPY --chown=webuser:webuser . /usr/share/nginx/html/

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
