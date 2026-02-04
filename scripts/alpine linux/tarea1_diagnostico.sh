echo -e "------------------------------------------------"
echo -e  "DIAGNOSTICO: SRV-ALPINELINUX-SISTEMAS"
echo -e "------------------------------------------------"

echo -e "Nombre del equipo:     $(hostname)"


IP_ETH1=$(ip addr show eth1 | grep "inet " | awk '{print $2}' | cut -d/ -f1)
echo -e "IP actual: 		${IP_ETH1:-'No asignada'}"

DISK_INFO=$(df -h | tail -1)
TOTAL=$(echo $DISK_INFO | awk '{print $2}')
USED=$(echo $DISK_INFO | awk '{print $3}')
AVAIL=$(echo $DISK_INFO | awk '{print $4}')

echo -e "Espacio en disco: $AVAIL disponibles de $TOTAL (usado: $USED)"

echo "==================================================="

