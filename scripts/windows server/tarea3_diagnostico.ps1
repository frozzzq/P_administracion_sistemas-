

function validacionIp {
    param([string]$mensaje, [bool]$opcional = $false)
    do {
        $ip = Read-Host $mensaje
        if ($opcional -and [string]::IsNullOrWhiteSpace($ip)) { return $null }
        if ($ip -match '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$') {
            return $ip
        }
        Write-Host "Formato IPv4 inválido. Reintente." -ForegroundColor Red
    } while ($true)
}

function GestionarIpFija {
    Write-Host "`n[Verificando Configuración de Red]" -ForegroundColor Cyan
    $interfaz = Get-NetIPInterface -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch "Loopback" } | Select-Object -First 1
    
    if ($interfaz.Dhcp -eq "Enabled") {
        Write-Host "ADVERTENCIA: El servidor tiene DHCP habilitado. Se requiere IP fija para DNS." -ForegroundColor Yellow
        $nuevaIp = validacionIp "Ingrese la IP estática para este servidor: "
        $mascara = Read-Host "Ingrese la máscara (ej. 24 para 255.255.255.0): "
        $gw = validacionIp "Ingrese el Gateway (Puerta de enlace): "
        
        Write-Host "Configurando IP estática..." -ForegroundColor Yellow
        New-NetIPAddress -InterfaceAlias $interfaz.InterfaceAlias -IPAddress $nuevaIp -PrefixLength $mascara -DefaultGateway $gw
        Write-Host "IP configurada con éxito." -ForegroundColor Green
    } else {
        $actual = (Get-NetIPAddress -InterfaceIndex $interfaz.InterfaceIndex -AddressFamily IPv4).IPAddress
        Write-Host "El servidor ya tiene una IP fija configurada: $actual" -ForegroundColor Green
    }
}

function ConfigurarDns {
    Write-Host "`n=== CONFIGURACION DE ZONA Y REGISTROS ===" -ForegroundColor Blue
    
    $dominio = Read-Host "Ingrese el nombre de la zona (ej: reprobados.com)"
    if ([string]::IsNullOrWhiteSpace($dominio)) { $dominio = "reprobados.com" }

    $hostname = Read-Host "Ingrese el hostname (ej: www)"
    if ([string]::IsNullOrWhiteSpace($hostname)) { $hostname = "www" }

    $ipDestino = validacionIp "Ingrese la IP a la que apuntara ${hostname}.${dominio} : "

    try {
        if (-not (Get-DnsServerZone -Name $dominio -ErrorAction SilentlyContinue)) {
            Add-DnsServerPrimaryZone -Name $dominio -ZoneFile "$dominio.dns"
            Write-Host "Zona $dominio creada." -ForegroundColor Green
        }
        
        Add-DnsServerResourceRecordA -Name $hostname -ZoneName $dominio -IPv4Address $ipDestino -AllowUpdateAny
        Write-Host "Registro configurado con exito." -ForegroundColor Green
    } catch {
        Write-Host "Error en la configuracion: $($_.Exception.Message)" -ForegroundColor Red
    }
} 

function borrarDominio{
    $borrar = read-host "ingrese el dominio que desea borrar (ej: reprobados.com)"
    if (get-DnsServerZone -name $borrar -erroraction silentlycontinue){
        try{
            remove-DnsServerZone -name $borrar -force
            write-host "el dominio $borrar a sido borrado correctamente" -foregroundcolor green
        } catch{
            write-host "error al eliminar el dominio: $($_.exception.message)" -foregroundcolor red
        }
    }else{
        write-host "error: el dominio $borrar no existe en el servidor"
    }
}

#do {
 #   Write-Host "`n--- MENU DNS ---" -ForegroundColor Yellow
  #  Write-Host "[1] Verificar Instalacion"
   # Write-Host "[4] Configurar DNS"
    #Write-Host "Escriba 'salir' para finalizar."

    #$opc = Read-Host "`nIngrese una opcion"

  #  switch($opc) {
   #     "1" { 
    #        if ((Get-WindowsFeature DNS).Installed) { Write-Host "Instalado" } else { Write-Host "No instalado" }
     #   }
      
      #  "4" { ConfigurarDns }
   # }
#} while ($opc -ne "salir")

do {
    Write-Host "======================================================================" -ForegroundColor Yellow
    Write-Host "                           SERVIDOR DNS                               "
    Write-Host "======================================================================" -ForegroundColor Yellow
    Write-Host "[1] - VERIFICAR INSTALACION DNS"
    Write-Host "[2] - INSTALAR SERVICIO DNS"
    Write-Host "[3] - REMOVER SERVICIO DNS"
    Write-Host "[4] - CONFIGURAR ZONA Y REGISTROS (reprobados.com)"
    write-Host "[5] - BORRAR DOMINIO"
    Write-Host "[6] - MONITOREO Y PRUEBAS"
    Write-Host "[7] - SALIR"

    $opc = Read-Host "`nIngrese una opción"

    switch($opc) {
        "1" { 
            $v = Get-WindowsFeature DNS
            if ($v.Installed) { Write-Host "DNS Instalado" -ForegroundColor Green } else { Write-Host "No instalado" -ForegroundColor Red }
        }
        "2" { Install-WindowsFeature DNS -IncludeManagementTools }
        "3" { Uninstall-WindowsFeature DNS -Remove }
        "4" {
            ConfigurarDns
        }
        "5" { borrarDominio }
        "6" { MonitoreoDns }
        "7" { $opc = "salir" }
    }
} while ($opc -ne "salir")