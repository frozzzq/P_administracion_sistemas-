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
		try{
			$resul = install-windowsfeature -name DHCP -includemanagementtools
		
			if($resul.restartneeded -eq "Yes"){
				write-host "REINICIO REQUERIDO PARA COMPLETAR." -foregroundcolor yellow
				$confirmar = read-host "desea reiniciar ahora? (si/no)"
				if ($confirmar -eq "si") {restart-computer} 
			}else{
				write-host "SERVICIO DHCP INSTALADO CON EXITO!" -foregroundcolor green		

			}
		
		}catch{
			write-host "error al instalar" -foregroundcolor red
		}
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




function configuracionDhcp{
	import-module dhcpserver -force
	function validacionIp 
	{
		param([string]$mensaje)
		do
		{
			$ip = read-host $mensaje
			if ($ip -as [ipaddress]) {return $ip}
			else {write-host "formato ipv4 invalido. reintente"}
		} while ($true)
	}


	write-host "===CONFIGURACION DEL SERVICIO DHCP===" -foregroundcolor darkblue

	$nombreScope = read-host "Ingrese un nombre para el scope: " 

	$rangoI = validacionIp "IP Inicial del rango: "
	$prefijoI = $rangoI.split('.')[0..2] -join '.'
	$octetoI = $rangoI.split('.')
	do{
		$rangoF = validacionIp "IP final del rango: "
		$prefijoF = $rangoF.split('.')[0..2] -join '.'
		$octetoF = $rangoI.split('.')
		if ([version]$rangoI -ge [version]$rangoF ){
			write-host "error, la ip inicial ($rangoI) no puede ser mayor que el rango final ($rangoF)" -foregroundcolor red	
		}
		elseif ($prefijoI -ne $prefijoF){
			write-host "error, la ip inicial debe ser del mismo rango que la ip final" -foregroundcolor red
		}
		else {
			write-host "las IPs son validas" -foregroundcolor green
			write-host "procediendo..." -foregroundcolor cyan
			write-host "CALCULANDO ID DE RED..." -foregroundcolor yellow
			$redId = $prefijoI + ".0"
			
			write-host "CALCULANDO MASCARA DE RED..." -foregroundcolor yellow
			if ($octetoI[0..2] -join '.' -eq $octetoF[0..2] -join '.'){
				$mascara = "255.255.255.0"
			}
			elseif ($octetoI[0..1] -join '.' -eq $octetoF[0..1] -join '.'){
				$mascara = "255.255.0.0"
			}
			else{
				$mascara = "255.0.0.0"
			}			
			write-host "mascara calculada: $mascara" -foregroundcolor gray
		
		}
	} while([version]$rangoI -ge [version]$rangoF -or $prefijoI -ne $prefijoF)
	


	$dns	= validacionIp "servidor DNS:	"

	write-host "ejemplo de lease time: 08:00:00 (8 horas) 'dias.hrs.min.seg'"
	$tiempolease = read-host "ingrese tiempo de concesion: " 
	
	write-host "aplicando configuracion..." -foregroundcolor cyan

	$params = @{
		Name		= $nombreScope
		StartRange	= $rangoI
		EndRange	= $rangoF
		SubnetMask	= $mascara
		LeaseDuration	= [timespan]$tiempolease
		State		= "Active"
	}


	try{
		add-DhcpServerv4Scope @params
		set-dhcpserverv4optionvalue -scopeid $redId -dnsserver $dns -force
		write-host "configuracion exitosa!" -foregroundcolor green
	}
	catch{
		write-host "error: $($_.Exception.message)" -foregroundcolor red
	}

}

function monitoreo{
	write-host "==================MONITOREO Y ESTADO DEL SERVICIO==================" -foregroundcolor blue
	$servicio = get-service -name DHCPServer -Erroraction silentlycontinue
	if ($servicio){
		$color = if ($servicio.status -eq "Running") {"green"} else {"red"}
		write-host "estado del servicio: " -nonewline
		write-host "$($servicio.Status)" -foregroundcolor $color
	} else{
		write-host "el servicio dhcp no esta instalado correctamente" -foregroundcolor red
		return
	}

	write-host "--------------------------------------------------------------------------"
	write-host "equipos conectados (leases activos): " -foregroundcolor yellow
	$ambitos = get-dhcpserverv4scope -erroraction silentlycontinue
	if ($ambitos) {
		$hayleases = $false
		foreach ($ambito in $ambitos){
			$leases = get-dhcpserverv4lease -scopeid $ambito.scopeid -erroraction silentlycontinue
			if ($leases) {
				$leases | select-object ipaddress, clientid, hostname, leaseexpirytime | format-table -autosize
				$hayleases = $true
			}
		}
		if (-not $hayleases){
			write-host "no hay equipos conectados actualmente" -foregroundcolor gray
		}
	} else{
		write-host "no hay ambitos (scopes) configurados"
	}
}

function menu{
	write-host "==================MENU DE OPCIONES==================" -foregroundcolor blue
	write-host "1. verificar instalacion dhcp" -foregroundcolor yellow
	write-host "2. instalar servicio" -foregroundcolor yellow
	write-host "3. desinstalar servicio (razon de practica)" -foregroundcolor yellow
	write-host "4. configuracion de servicio dhcp" -foregroundcolor yellow
	write-host "5. monitoreo de servicio "-foregroundcolor yellow
}

do {
	menu

	$opcion = read-host "ingrese una opcion: "

	switch ($opcion) {
		"1" {verificarInstalacion}
		"2" {instalacion}
		"3" {desinstalacion}
		"4" {configuracionDhcp}
		"5" {monitoreo}
		default {write-host "opcion invalida!" -foregroundcolor red}
	}
	$choice = read-host "escribe 'si' para continuar"
}while ($choice -ne "si")
write-host "procediendo..." -foregroundcolor cyan


