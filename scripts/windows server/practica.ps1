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
		write-host "deteniendo proceso en memoria..." foregroundcolor yellow
		stop-service -name DHCPServer -force -erroraction silentlycontinue
	
		$res = uninstall-windowsfeature -name DHCP -includemanagementtools
		if ($res.success){
			write-host "desinstalacion exitosa!" -foregroundcolor green
			if ($res.restartneeded -eq "Yes"){
				write-host "advertencia: se necesita un reinicio" -foregroundcolor red
			}
		}
	}
	else 
	{
		write-host "servicio no instalado, por lo tanto no se puede desinstalar" -foregroundcolor red
		
	}
}




function configuracionDhcp{
	import-module dhcpserver -force
	function validacionIp {
    param([string]$mensaje, [bool]$opcional = $false)
    do {
        $ip = read-host $mensaje
        if ($opcional -and [string]::IsNullOrWhiteSpace($ip)) { return $null }

        # Validamos formato básico y que no haya ceros a la izquierda usando Regex
        # Esta expresión regular evita que un octeto empiece con 0 a menos que sea solo '0'
        if ($ip -match '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$') {
            
            $octetos = $ip.Split('.')
            $errorCero = $false

            foreach ($octeto in $octetos) {
                if ($octeto.Length -gt 1 -and $octeto.StartsWith("0")) {
                    $errorCero = $true
                    break
                }
            }

            if ($errorCero) {
                write-host "error: no se permiten ceros a la izquierda (ej. use '1' en lugar de '01')" -foregroundcolor red
                continue
            }

            # Validaciones de rangos especiales (usando [int] para evitar errores de tipo)
            $primerOcteto = [int]$octetos[0]
            
            if ($ip -eq "0.0.0.0") { write-host "error: 0.0.0.0 reservada" -foregroundcolor red }
            elseif ($ip -eq "255.255.255.255") { write-host "error: Global Broadcast" -foregroundcolor red }
            elseif ($primerOcteto -eq 127) { write-host "error: Rango Loopback" -foregroundcolor red }
            elseif ($primerOcteto -ge 224) { write-host "error: IP Multicast o Reservada ($primerOcteto)" -foregroundcolor red }
            else { return $ip }
        }
        else {
            write-host "formato ipv4 invalido o fuera de rango (0-255). reintente" -foregroundcolor red
        }
    } while ($true)



	write-host "===CONFIGURACION DEL SERVICIO DHCP===" -foregroundcolor darkblue

	$nombreScope = read-host "Ingrese un nombre para el scope: " 

	$rangoI = validacionIp "IP Inicial del rango: "
	$prefijoI = $rangoI.split('.')[0..2] -join '.'
	$octetoI = $rangoI.split('.')

	write-host "configurando la ip fija del servidor ($rangoI)..." -foregroundcolor yellow
	try{
		$interfaz = (get-netadapter | where-object status -eq "Up" | select-object -first 1).name
		remove-netipaddress -interfacealias "Ethernet 2" -confirm:$false -erroraction silentlycontinue
		new-netipaddress -interfacealias "Ethernet 2" -ipaddress $rangoI -prefixlength 24 -erroraction silentlycontinue
		set-dhcpserverv4binding -bindingstate $true -interfacealias "Ethernet 2"
		write-host "servidor ahora tiene la ip: $rangoI" -foregroundcolor green
	} catch{
		write-host "no se puede cambiar la ip del servidor: $($_.exception.message)" -foregroundcolor yellow
	}

	$ipSplit = $rangoI.split('.')
	$ultimoOcteto = [int]$ipSplit[3] + 1
	$rangoDhcpInicio = "$($ipSplit[0..2] -join '.').$ultimoOcteto"
	write-host "el rango de clientes empezara en: $rangoDhcpInicio" -foregroundcolor gray
	do{
		$rangoF = validacionIp "IP final del rango: "
		$prefijoF = $rangoF.split('.')[0..2] -join '.'
		$octetoF = $rangoF.split('.')
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
	if (-not [string]::isnullorwhitespace($dns)) {
		
		write-host "dns configurado: $dns" -foregroundcolor green
	}

	$gateway = read-host "ingrese la ip del gateway/puerta de enlace (deje en blanco para saltar"
	if (-not [string]::isnullorwhitespace($gateway)) {
		set-dhcpserverv4optionvalue -scopeid $redId -optionid 3 -value $gateway
		write-host "gateway configurado: $gateway" -foregroundcolor green
	}

	write-host "ejemplo de lease time: 08:00:00 (8 horas) 'dias.hrs.min.seg'"
	$tiempolease = read-host "ingrese tiempo de concesion: " 
	
	write-host "aplicando configuracion..." -foregroundcolor cyan

	$params = @{
		Name		= $nombreScope
		StartRange	= $rangoDhcpInicio
		EndRange	= $rangoF
		SubnetMask	= $mascara
		LeaseDuration	= [timespan]$tiempolease
		State		= "Active"
	}


	try{
		add-DhcpServerv4Scope @params
		set-dhcpserverv4optionvalue -scopeid $redId -optionid 6 -value $dns
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
	try{
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
	}catch{
		write-host "no existe el servicio o no hay clientes disponibles" -foregroundcolor yellow

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
}while ($choice -eq "si")
write-host "procediendo..." -foregroundcolor cyan


