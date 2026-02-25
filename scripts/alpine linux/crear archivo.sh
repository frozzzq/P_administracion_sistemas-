# Crear el archivo mínimo para que el servicio no dé error al iniciar
cat <<EOF > /etc/bind/named.conf
options {
    directory "/var/bind";
    allow-query { any; };
    listen-on { any; };
};

include "/etc/bind/named.conf.local";
EOF
