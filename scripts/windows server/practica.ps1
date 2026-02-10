write-host "===================================================" -foregroundcolor blue
write-host "=================PRUEBA DE SCRIPT==================" -foregroundcolor yellow
write-host "===================================================" -foregroundcolor blue

function verificarInstalacion {
	write-host "Verificando la instalacion DHCP..." -foregroundcolor yellow
	$feature = get-windowsfeature -name DHCP

	if ($feature.installed) 
	{
		write-host "SERVICIO DHCP INSTALADO" -foregroundcolor green
	}
	else 
	{
		write-host "SERVICIO DHCP NO INSTALADO" -foregroundcolor red
		write-host "sugerencia!... use la opcion de instalar el servicio" -foregroundcolor yellow
	}
}

function instalacion {

	write-host " INICIANDO INSTALACION..." -foregroundcolor cyan
	$check = get-windowsfeature -name DHCP

	if ($check.installed) 
	{
		write-host "SERVICIO DHCP INSTALADO, (no es necesario una instalacion)" -foregroundcolor green
	}
	else 
	{
		install-windowsfeature -name DHCP -includemanagementtools
		write-host "SERVICIO DHCP INSTALADO CON EXITO!" -foregroundcolor green		
	}
}


function desinstalacion{
	write-host "INICIANDO DESINSTALACION..." -foregroundcolor darkmagenta
	$check = get-windowsfeature -name DHCP
	
	if ($check.installed) 
	{
		uninstall-windowsfeature -name DHCP -includemanagementtools
		write-host "desinstalacion exitosa!" -foregroundcolor green
	}
	else 
	{
		write-host "servicio no instalado, por lo tanto no se puede desinstalar" -foregroundcolor red
		
	}
}

function menu{
	write-host "==================MENU DE OPCIONES==================" -foregroundcolor blue
	write-host "1. verificar instalacion dhcp" -foregroundcolor yellow
	write-host "2. instalar servicio" -foregroundcolor yellow
	write-host "3. desinstalar servicio (razon de practica)" -foregroundcolor yellow
}

do {
	menu

	$opcion = read-host "ingrese una opcion: "

	switch ($opcion) {
		"1" {verificarInstalacion}
		"2" {instalacion}
		"3" {desinstalacion}
		default {write-host "opcion invalida!" -foregroundcolor red}
	}
	$choice = read-host "escribe 'si' para continuar"
}while ($choice -ne "si")
write-host "procediendo..." -foregroundcolor cyan


