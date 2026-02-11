echo "VERIFICANDO INSTALACION DE ISC-DHCP-SERVER..."
if ! command -v dhcpd >/dev/mull 2>&1; then
	echo "instalando servicio de forma desatendida..."
	apk add isc-dhcp-server
else 
	echo "el servicio ya esta instalado. omitiendo..."
fi
