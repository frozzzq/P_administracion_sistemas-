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




function configuracionDhcp {
    import-module dhcpserver -force
    
    # ... (Mantén tu función validacionIp aquí adentro como la tienes) ...

    write-host "=== CONFIGURACION DEL SERVICIO DHCP ===" -foregroundcolor darkblue

    $nombreScope = read-host "Ingrese un nombre para el scope" 
    $rangoI = validacionIp "IP Inicial del rango (IP del Servidor)"
    $prefijoI = $rangoI.split('.')[0..2] -join '.'
    
    # --- Configuración de IP Fija en el Servidor ---
    write-host "Configurando IP fija en el servidor ($rangoI)..." -foregroundcolor yellow
    try {
        # ¡OJO! Asegúrate de que tu interfaz se llame "Ethernet 2"
        remove-netipaddress -interfacealias "Ethernet 2" -confirm:$false -erroraction silentlycontinue
        new-netipaddress -interfacealias "Ethernet 2" -ipaddress $rangoI -prefixlength 24 -erroraction silentlycontinue
        set-dhcpserverv4binding -bindingstate $true -interfacealias "Ethernet 2"
    } catch {
        write-host "Aviso: No se pudo cambiar la IP (quizás ya está configurada): $($_.exception.message)" -foregroundcolor yellow
    }

    # --- Cálculo de Rango y Máscara ---
    $rangoDhcpInicio = "$prefijoI.$([int]($rangoI.split('.')[3]) + 1)"
    do {
        $rangoF = validacionIp "IP final del rango"
        $prefijoF = $rangoF.split('.')[0..2] -join '.'
        if ([version]$rangoI -ge [version]$rangoF) { write-host "Error: IP inicial mayor a final" -foregroundcolor red }
    } while ([version]$rangoI -ge [version]$rangoF -or $prefijoI -ne $prefijoF)

    $redId = $prefijoI + ".0"
    $mascara = "255.255.255.0" # Simplificado para el ejemplo

    # --- Captura de Datos Opcionales ---
    $dns = validacionIp "Servidor DNS (Enter para saltar)" $true
    
    # AQUÍ ESTÁ EL CAMBIO: El gateway se guarda pero NO se aplica todavía
    $gateway = read-host "Ingrese la IP del Gateway (Enter para saltar)"
    
    $tiempolease = read-host "Ingrese tiempo de concesion (ej: 08:00:00)"
    if ([string]::IsNullOrWhiteSpace($tiempolease)) { $tiempolease = "08:00:00" }

    # --- Aplicación de Configuración ---
    write-host "Aplicando configuracion..." -foregroundcolor cyan
    try {
        # 1. CREAR EL SCOPE (Esto es lo primero)
        add-DhcpServerv4Scope -Name $nombreScope -StartRange $rangoDhcpInicio -EndRange $rangoF -SubnetMask $mascara -LeaseDuration ([timespan]$tiempolease) -State "Active"

        # 2. APLICAR DNS SI EXISTE
        if (-not [string]::IsNullOrWhiteSpace($dns)) {
            set-dhcpserverv4optionvalue -scopeid $redId -dnsserver $dns -force
        }

        # 3. APLICAR GATEWAY SI EXISTE (Ahora sí funciona porque el Scope ya existe)
        if (-not [string]::IsNullOrWhiteSpace($gateway)) {
            set-dhcpserverv4optionvalue -scopeid $redId -optionid 3 -value $gateway
            write-host "Gateway configurado: $gateway" -foregroundcolor green
        }

        write-host "¡Configuracion exitosa!" -foregroundcolor green
    } catch {
        write-host "Error critico: $($_.Exception.message)" -foregroundcolor red
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


