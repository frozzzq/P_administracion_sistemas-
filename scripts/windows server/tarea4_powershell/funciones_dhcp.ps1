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
    
	
function validacionIp {
    param([string]$mensaje, [bool]$opcional = $false)
    do {
        $ip = read-host $mensaje
        if ($opcional -and [string]::IsNullOrWhiteSpace($ip)) { return $null }

       
        if ($ip -match '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$') {
            $octetos = $ip.Split('.')
            $errorCero = $false
            foreach ($octeto in $octetos) {
                if ($octeto.Length -gt 1 -and $octeto.StartsWith("0")) {
                    $errorCero = $true; break
                }
            }
            if ($errorCero) {
                write-host "Error: No ceros a la izquierda." -foregroundcolor red
                continue
            }
            return $ip
        } else {
            write-host "Formato invalido. Reintente." -foregroundcolor red
        }
    } while ($true)
}

function configuracionDhcp {
    import-module dhcpserver -force
    write-host "===CONFIGURACION DEL SERVICIO DHCP===" -foregroundcolor darkblue

    $nombreScope = read-host "Ingrese un nombre para el scope" 
    
  
    $rangoI = validacionIp "IP Inicial del rango (IP Servidor): "
    if ($null -eq $rangoI) { return }
    
    $prefijoI = $rangoI.split('.')[0..2] -join '.'



    do {
        $rangoF = validacionIp "IP final del rango: "
        
       
        if ($null -ne $rangoF) {
            $prefijoF = $rangoF.split('.')[0..2] -join '.'
            
            if ([version]$rangoI -ge [version]$rangoF) {
                write-host "Error: IP Inicial debe ser menor a Final." -foregroundcolor red
                $rangoF = $null 
            } elseif ($prefijoI -ne $prefijoF) {
                write-host "Error: Deben estar en la misma subred ($prefijoI.x)" -foregroundcolor red
                $rangoF = $null
            }
        }
    } while ($null -eq $rangoF)

   
    $gateway = read-host "IP Gateway (Enter para saltar)"
    
  
    try {
        $redId = "$prefijoI.0"
        Add-DhcpServerv4Scope -Name $nombreScope -StartRange "$prefijoI.10" -EndRange $rangoF -SubnetMask "255.255.255.0"
        
        if (-not [string]::IsNullOrWhiteSpace($gateway)) {
            Set-DhcpServerv4OptionValue -ScopeId $redId -OptionId 3 -Value $gateway
        }
        write-host "¡Scope configurado con éxito!" -foregroundcolor green
    } catch {
        write-host "Error al crear scope: $($_.Exception.Message)" -foregroundcolor red
    }
}


    write-host "=== CONFIGURACION DEL SERVICIO DHCP ===" -foregroundcolor darkblue

    $nombreScope = read-host "Ingrese un nombre para el scope" 
    $rangoI = validacionIp "IP Inicial del rango (IP del Servidor)"
    $prefijoI = $rangoI.split('.')[0..2] -join '.'
    

    write-host "Configurando IP fija en el servidor ($rangoI)..." -foregroundcolor yellow
    try {
       
        remove-netipaddress -interfacealias "Ethernet 2" -confirm:$false -erroraction silentlycontinue
        new-netipaddress -interfacealias "Ethernet 2" -ipaddress $rangoI -prefixlength 24 -erroraction silentlycontinue
        set-dhcpserverv4binding -bindingstate $true -interfacealias "Ethernet 2"
    } catch {
        write-host "Aviso: No se pudo cambiar la IP (quizás ya está configurada): $($_.exception.message)" -foregroundcolor yellow
    }


    $rangoDhcpInicio = "$prefijoI.$([int]($rangoI.split('.')[3]) + 1)"
    do {
        $rangoF = validacionIp "IP final del rango"
        $prefijoF = $rangoF.split('.')[0..2] -join '.'
        if ([version]$rangoI -ge [version]$rangoF) { write-host "Error: IP inicial mayor a final" -foregroundcolor red }
    } while ([version]$rangoI -ge [version]$rangoF -or $prefijoI -ne $prefijoF)

    $redId = $prefijoI + ".0"
    $mascara = "255.255.255.0" 

   
    $dns = validacionIp "Servidor DNS (Enter para saltar)" $true
    
   
    $gateway = read-host "Ingrese la IP del Gateway (Enter para saltar)"
    
    $tiempolease = read-host "Ingrese tiempo de concesion (ej: 08:00:00)"
    if ([string]::IsNullOrWhiteSpace($tiempolease)) { $tiempolease = "08:00:00" }

    write-host "Aplicando configuracion..." -foregroundcolor cyan
    try {
       
        add-DhcpServerv4Scope -Name $nombreScope -StartRange $rangoDhcpInicio -EndRange $rangoF -SubnetMask $mascara -LeaseDuration ([timespan]$tiempolease) -State "Active"

   
        if (-not [string]::IsNullOrWhiteSpace($dns)) {
            set-dhcpserverv4optionvalue -scopeid $redId -dnsserver $dns -force
        }

       
        if (-not [string]::IsNullOrWhiteSpace($gateway)) {
            set-dhcpserverv4optionvalue -scopeid $redId -optionid 3 -value $gateway
            write-host "Gateway configurado: $gateway" -foregroundcolor green
        }

        write-host "¡Configuracion exitosa!" -foregroundcolor green
    } catch {
        write-host "Error critico: $($_.Exception.message)" -foregroundcolor red
    }
}
function borrarScopes{
	try{
		Get-DhcpServerv4Scope | Remove-DhcpServerv4Scope -Force
	}catch{
		write-host "error al borrar scopes: $($_.exception.message)"
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
function menuDhcp {
    Write-Host "`n========================================" -ForegroundColor Blue
    Write-Host "        GESTIÓN DE SERVICIO DHCP         " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Blue
    Write-Host "1. Verificar instalacion"              -ForegroundColor Yellow
    Write-Host "2. instalar servicio"            -ForegroundColor Yellow
    Write-Host "3. desinstalar servicio"                      -ForegroundColor Yellow
    Write-Host "4. Volver al menú principal"             -ForegroundColor Yellow
    Write-Host "5. borrar scopes"             -ForegroundColor Yellow
    Write-Host "6. monitoreo"             -ForegroundColor Yellow
    Write-Host "7. volver a menu principal"             -ForegroundColor Yellow

    $op = Read-Host "`nElige una opción"
    switch ($op) {
        "1" { verificarInstalacion }
        "2" { instalacion }
        "3" { desinstalacion }
        "4" { configuracionDhcp }
        "5" { borrarScopes }
        "6" { monitoreo }
        "7" { return }
        default { Write-Host "Opción inválida." -ForegroundColor Red }
    }
}