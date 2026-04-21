# Practica 7 - Instalacion Hibrida con SSL/TLS (Windows)
# Archivo unico: funciones + logica principal combinados
# No requiere windows-funciones_http.ps1 en la misma carpeta

# ============================================================
# windows-funciones_http.ps1
# Funciones para gestion de servidores HTTP en Windows Server 2022 Core
# ============================================================

# =============== MENSAJES ===============
function Write-Ok    { param($msg) Write-Host "[+] $msg" -ForegroundColor Green  }
function Write-Info  { param($msg) Write-Host "[i] $msg" -ForegroundColor Cyan   }
function Write-Err   { param($msg) Write-Host "[x] $msg" -ForegroundColor Red    }
function Write-Warn  { param($msg) Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Title { param($msg) Write-Host "`n---- $msg ----`n" -ForegroundColor Magenta }

# =============== RECARGAR PATH ===============
function Refrescar-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
}

# =============== CHOCOLATEY ===============
function Asegurar-Chocolatey {
    Refrescar-Path
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Info "Chocolatey disponible."
        return
    }
    Write-Info "Instalando Chocolatey..."
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol =
            [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression (
            (New-Object System.Net.WebClient).DownloadString(
                'https://community.chocolatey.org/install.ps1'
            )
        ) 2>&1 | Out-Null
        Refrescar-Path
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Write-Ok "Chocolatey instalado correctamente."
            return
        }
        $chocoDir = "$env:ALLUSERSPROFILE\chocolatey\bin"
        if (Test-Path "$chocoDir\choco.exe") {
            $env:Path += ";$chocoDir"
            Write-Ok "Chocolatey instalado (PATH actualizado manualmente)."
        } else {
            Write-Err "No se pudo instalar Chocolatey. Verifica la conexion a internet."
            exit 1
        }
    } catch {
        Write-Err "Error instalando Chocolatey: $_"
        exit 1
    }
}

# =============== VALIDAR PUERTO ===============
function validarPuerto {
    param([int]$puerto)
    $reservados = @(21, 22, 23, 25, 53, 443, 3306, 3389, 5432, 6379, 27017)
    if ($reservados -contains $puerto) {
        Write-Warn "Puerto $puerto reservado para otro servicio."
        return $false
    }
    $enUso = Get-NetTCPConnection -LocalPort $puerto -ErrorAction SilentlyContinue
    if ($enUso) {
        $proc = Get-Process -Id $enUso[0].OwningProcess -ErrorAction SilentlyContinue
        Write-Warn "Puerto $puerto ocupado por: $($proc.ProcessName) (PID: $($enUso[0].OwningProcess))"
        return $false
    }
    return $true
}

# =============== PEDIR PUERTO ===============
function pedirPuerto {
    param([int]$default = 80)
    Write-Host ""
    Write-Host "=== Configuracion de Puerto ===" -ForegroundColor Blue
    Write-Info "Puerto por defecto : $default"
    Write-Info "Otros comunes      : 8080, 8888"
    Write-Info "Bloqueados         : 21 22 23 25 53 443 3306 3389 5432 6379 27017"
    Write-Host ""
    while ($true) {
        $inp = Read-Host "Puerto de escucha (Enter = $default)"
        if ([string]::IsNullOrWhiteSpace($inp)) { $inp = "$default" }
        if ($inp -notmatch '^\d+$') { Write-Warn "Ingresa solo numeros."; continue }
        $puerto = [int]$inp
        if ($puerto -ne 80 -and ($puerto -lt 100 -or $puerto -gt 65535)) {
            Write-Warn "Puerto fuera de rango. Usa 80 o entre 1024 y 65535."
            continue
        }
        if (validarPuerto -puerto $puerto) {
            Write-Ok "Puerto $puerto aceptado."
            return $puerto
        }
    }
}

# =============== FIREWALL ===============
function configurarFirewall {
    param([int]$puertoNuevo, [int]$puertoViejo = 80, [string]$nombreServicio = "HTTP")
    Write-Info "Configurando firewall..."
    Remove-NetFirewallRule -DisplayName "HTTP-$nombreServicio-$puertoViejo" -ErrorAction SilentlyContinue
    New-NetFirewallRule `
        -DisplayName "HTTP-$nombreServicio-$puertoNuevo" `
        -Direction Inbound -Protocol TCP -LocalPort $puertoNuevo `
        -Action Allow -Profile Any | Out-Null
    Write-Ok "Firewall: puerto $puertoNuevo abierto para $nombreServicio."
}

# =============== CREAR INDEX.HTML ===============
function crearHTML {
    param([string]$rutaWeb, [string]$servicio, [string]$version, [int]$puerto)
    if (-not (Test-Path $rutaWeb)) {
        New-Item -ItemType Directory -Path $rutaWeb -Force | Out-Null
    }
    # Usar WriteAllText con UTF8 sin BOM para evitar errores en nginx/apache
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $contenido = @"
<!DOCTYPE html>
<html lang="es">
<head><meta charset="UTF-8"><title>Servidor HTTP - Windows</title></head>
<body>
<h1>Windows - Servidor Activo</h1>
<p>Servidor: $servicio</p>
<p>Version: $version</p>
<p>Puerto: $puerto</p>
</body>
</html>
"@
    [System.IO.File]::WriteAllText("$rutaWeb\index.html", $contenido, $utf8NoBom)
    Write-Ok "index.html creado en $rutaWeb"
}

# =============== BUSCAR RUTA NGINX ===============
function Obtener-Ruta-Nginx {
    # Choco v2 instala en: C:\ProgramData\chocolatey\lib\nginx\tools\nginx-VERSION\
    $libPath = "C:\ProgramData\chocolatey\lib\nginx\tools"
    if (Test-Path $libPath) {
        $exe = Get-ChildItem $libPath -Filter "nginx.exe" -Recurse `
            -ErrorAction SilentlyContinue -Depth 3 | Select-Object -First 1
        if ($exe) { return $exe.DirectoryName }
    }
    # Choco v1/herramienta instala en C:\tools\nginx-VERSION\
    if (Test-Path "C:\tools") {
        $exe = Get-ChildItem "C:\tools" -Filter "nginx.exe" -Recurse `
            -ErrorAction SilentlyContinue -Depth 5 | Select-Object -First 1
        if ($exe) { return $exe.DirectoryName }
    }
    # Rutas directas alternativas
    foreach ($r in @("C:\nginx", "C:\nginx\nginx")) {
        if (Test-Path "$r\nginx.exe") { return $r }
    }
    # Busqueda amplia - excluir bin\ de choco (es shim, no el exe real)
    $exe = Get-ChildItem "C:\" -Filter "nginx.exe" -Recurse `
        -ErrorAction SilentlyContinue -Depth 7 |
        Where-Object { $_.FullName -notlike "*\bin\*" } |
        Select-Object -First 1
    if ($exe) { return $exe.DirectoryName }
    return $null
}
# =============== INSTALAR IIS ===============
function instalarIIS {
    param([int]$puerto)
    Write-Title "Instalando IIS..."
    $winVer = (Get-WmiObject Win32_OperatingSystem).Caption
    $iisVersion = switch -Wildcard ($winVer) {
        "*Server 2022*" { "10.0" } "*Server 2019*" { "10.0" }
        "*Server 2016*" { "10.0" } "*Server 2012*" { "8.5"  }
        "*Windows 1*"   { "10.0" } default          { "10.0" }
    }
    Write-Info "Sistema: $winVer"
    Write-Info "Version IIS disponible: $iisVersion (determinada por Windows)"
    Write-Host ""
    $confirmar = Read-Host "Instalar IIS $iisVersion en puerto $puerto? (s/n)"
    if ($confirmar -ne 's') { return }

    $features = @("Web-Server","Web-Common-Http","Web-Static-Content",
                  "Web-Default-Doc","Web-Http-Errors","Web-Security",
                  "Web-Filtering","Web-Http-Logging","Web-Stat-Compression")
    foreach ($f in $features) {
        Install-WindowsFeature -Name $f -ErrorAction SilentlyContinue | Out-Null
    }
    Write-Ok "IIS instalado."

    $appcmd = "$env:SystemRoot\system32\inetsrv\appcmd.exe"
    & $appcmd set site "Default Web Site" /bindings:"http/*:${puerto}:" 2>&1 | Out-Null
    Write-Ok "Puerto configurado: $puerto"

    $webConfig = "$env:SystemDrive\inetpub\wwwroot\web.config"
    Set-Content -Path $webConfig -Encoding UTF8 -Value @"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <security>
      <requestFiltering removeServerHeader="true">
        <verbs>
          <add verb="TRACE" allowed="false" />
          <add verb="TRACK" allowed="false" />
        </verbs>
      </requestFiltering>
    </security>
    <httpProtocol>
      <customHeaders>
        <remove name="X-Powered-By" />
        <add name="X-Frame-Options"        value="SAMEORIGIN" />
        <add name="X-Content-Type-Options" value="nosniff"    />
      </customHeaders>
    </httpProtocol>
  </system.webServer>
</configuration>
"@
    Write-Ok "Seguridad configurada (web.config)."

    $webroot = "$env:SystemDrive\inetpub\wwwroot"
    $acl  = Get-Acl $webroot
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "IIS_IUSRS","ReadAndExecute","ContainerInherit,ObjectInherit","None","Allow")
    $acl.SetAccessRule($rule)
    Set-Acl $webroot $acl
    Write-Ok "Permisos aplicados: IIS_IUSRS -> ReadAndExecute."

    crearHTML -rutaWeb $webroot -servicio "IIS" -version $iisVersion -puerto $puerto
    configurarFirewall -puertoNuevo $puerto -puertoViejo 80 -nombreServicio "IIS"

    Start-Service W3SVC -ErrorAction SilentlyContinue
    Set-Service   W3SVC -StartupType Automatic
    Start-Sleep -Seconds 2

    $svc = Get-Service W3SVC -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Write-Ok "IIS activo en puerto $puerto"
    } else {
        Write-Err "IIS no arranco. Revisa el Visor de Eventos."
    }
}

# =============== INSTALAR APACHE ===============
function instalarApache {
    param(
        [int]$puerto,
        [string]$archivoLocal = ""
    )
    Write-Title "Instalando Apache HTTP Server..."
    
    $versionElegida = ""
    $apacheRoot = ""
    
    # Si viene archivo local (FTP), instalar desde ahí
    if ($archivoLocal -and (Test-Path $archivoLocal)) {
        Write-Info "Instalando desde archivo local: $archivoLocal"
        
        # Extraer versión del nombre del archivo
        $nombreArchivo = [System.IO.Path]::GetFileNameWithoutExtension($archivoLocal)
        if ($nombreArchivo -match 'httpd-(\d+\.\d+\.\d+)') {
            $versionElegida = $matches[1]
        } elseif ($nombreArchivo -match 'apache.*?(\d+\.\d+\.\d+)') {
            $versionElegida = $matches[1]
        } else {
            $versionElegida = "local"
        }
        
        # Instalar en C:\Apache24
        $apacheRoot = "C:\Apache24"
        
        Write-Info "Extrayendo a: $apacheRoot..."
        
        # Limpiar instalación anterior si existe
        if (Test-Path $apacheRoot) {
            Write-Warn "Eliminando instalacion anterior..."
            Stop-Service Apache* -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            Remove-Item -Path $apacheRoot -Recurse -Force
        }
        
        # Extraer ZIP
        try {
            # Crear directorio temporal para extracción
            $tempExtract = "$env:TEMP\apache_extract"
            if (Test-Path $tempExtract) {
                Remove-Item -Path $tempExtract -Recurse -Force
            }
            New-Item -ItemType Directory -Path $tempExtract -Force | Out-Null
            
            Expand-Archive -Path $archivoLocal -DestinationPath $tempExtract -Force
            
            # Buscar carpeta Apache*/Apache24 dentro del ZIP
            $apacheFolders = Get-ChildItem -Path $tempExtract -Directory -Recurse | Where-Object { 
                $_.Name -match '^Apache' -and (Test-Path "$($_.FullName)\bin\httpd.exe")
            }
            
            if ($apacheFolders) {
                $sourceFolder = $apacheFolders[0].FullName
                Write-Info "Copiando desde: $sourceFolder"
                
                # Crear C:\Apache24 y copiar
                New-Item -ItemType Directory -Path $apacheRoot -Force | Out-Null
                Copy-Item -Path "$sourceFolder\*" -Destination $apacheRoot -Recurse -Force
                
                # Limpiar temporal
                Remove-Item -Path $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
                
                Write-Ok "Apache extraido correctamente"
            } else {
                Write-Err "No se encontro httpd.exe en el archivo"
                return
            }
        } catch {
            Write-Err "Error al extraer: $_"
            return
        }
        
    } else {
        # Instalación desde WEB (Chocolatey)
        Asegurar-Chocolatey

        Write-Info "Consultando versiones disponibles de apache-httpd..."
        $rawVersiones = choco search apache-httpd --exact --all-versions --limit-output 2>$null
        $versiones = @()
        foreach ($linea in $rawVersiones) {
            if ($linea -match '\|') {
                $ver = ($linea -split '\|')[1].Trim()
                if ($ver -match '^\d+\.\d+' -and $versiones -notcontains $ver) { $versiones += $ver }
            }
        }
        if ($versiones.Count -eq 0) { Write-Err "No se encontraron versiones. Verifica internet."; return }

        Write-Host ""
        Write-Host "Versiones disponibles:" -ForegroundColor Cyan
        $limite = [Math]::Min($versiones.Count, 3)
        for ($i = 0; $i -lt $limite; $i++) {
            $etiqueta = switch ($i) {
                0 { "[Latest - Desarrollo]" } 1 { "[Estable anterior]" } 2 { "[LTS]" }
            }
            Write-Host "  $($i+1). $($versiones[$i])  $etiqueta"
        }
        Write-Host ""
        do { $selVer = Read-Host "Selecciona version (1-$limite)" } while ($selVer -notmatch "^[1-$limite]$")
        $versionElegida = $versiones[[int]$selVer - 1]

        Write-Info "Instalando Apache $versionElegida en puerto $puerto..."
        choco install apache-httpd `
            --version="$versionElegida" `
            --params="`"/port:$puerto /installLocation:C:\Apache24`"" `
            --yes --no-progress --force 2>&1 | Out-Null

        if ($LASTEXITCODE -ne 0) { Write-Err "Fallo la instalacion. Codigo: $LASTEXITCODE"; return }
        Refrescar-Path

        # Buscar donde quedo instalado
        $posibles = @("C:\Apache24","$env:APPDATA\Apache24","$env:LOCALAPPDATA\Apache24")
        $apacheRoot = $posibles | Where-Object { Test-Path "$_\bin\httpd.exe" } | Select-Object -First 1
        if (-not $apacheRoot) {
            $httpd = Get-ChildItem "C:\" -Filter "httpd.exe" -Recurse `
                -ErrorAction SilentlyContinue -Depth 6 | Select-Object -First 1
            if ($httpd) { $apacheRoot = Split-Path (Split-Path $httpd.FullName) }
        }
        if (-not $apacheRoot) { Write-Err "No se encontro httpd.exe."; return }
    }
    if (-not $apacheRoot) { Write-Err "No se encontro la instalacion de Apache."; return }

    Write-Ok "Apache instalado en: $apacheRoot"

    $httpdConf = "$apacheRoot\conf\httpd.conf"
    if (Test-Path $httpdConf) {
        $conf = Get-Content $httpdConf -Raw
        if ($conf -notmatch "Listen\s+$puerto") {
            $conf = $conf -replace 'Listen\s+\d+', "Listen $puerto"
            Set-Content $httpdConf $conf -Encoding UTF8
            Write-Ok "Puerto $puerto aplicado en httpd.conf."
        }
        if ($conf -notmatch 'TAREA6-SECURITY') {
            Add-Content -Path $httpdConf -Value @"

# TAREA6-SECURITY-START
ServerTokens Prod
ServerSignature Off

# LimitExcept debe ir dentro de un bloque <Directory>
<Directory "/">
    <LimitExcept GET POST HEAD>
        Require all denied
    </LimitExcept>
</Directory>

Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-Content-Type-Options "nosniff"
# TAREA6-SECURITY-END
"@
            Write-Ok "Seguridad configurada en httpd.conf."
        }
    }

    crearHTML -rutaWeb "$apacheRoot\htdocs" -servicio "Apache HTTP Server" -version $versionElegida -puerto $puerto
    configurarFirewall -puertoNuevo $puerto -puertoViejo 80 -nombreServicio "Apache"

    $svc = Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "^Apache" } | Select-Object -First 1
    if (-not $svc) {
        $httpdExe = "$apacheRoot\bin\httpd.exe"
        if (Test-Path $httpdExe) {
            Write-Info "Registrando servicio Apache..."
            & $httpdExe -k install 2>&1 | Out-Null
            Start-Sleep -Seconds 2
            $svc = Get-Service -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match "^Apache" } | Select-Object -First 1
        }
    }
    if ($svc) {
        Start-Service $svc.Name -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        $svc = Get-Service $svc.Name -ErrorAction SilentlyContinue
        if ($svc.Status -eq "Running") {
            Write-Ok "Apache activo en puerto $puerto"
        } else {
            Write-Err "Apache no arranco. Revisa: $apacheRoot\logs\error.log"
        }
    } else {
        Write-Err "No se pudo registrar el servicio Apache."
    }
}

# =============== INSTALAR NGINX ===============
function instalarNginx {
    param(
        [int]$puerto,
        [string]$archivoLocal = ""
    )
    Write-Title "Instalando Nginx..."
    
    $versionElegida = ""
    $nginxRoot = ""
    
    # Si viene archivo local (FTP), instalar desde ahí
    if ($archivoLocal -and (Test-Path $archivoLocal)) {
        Write-Info "Instalando desde archivo local: $archivoLocal"
        
        # Extraer versión del nombre del archivo
        $nombreArchivo = [System.IO.Path]::GetFileNameWithoutExtension($archivoLocal)
        if ($nombreArchivo -match 'nginx-(\d+\.\d+\.\d+)') {
            $versionElegida = $matches[1]
        } else {
            $versionElegida = "local"
        }
        
        # Determinar carpeta de instalación
        $nginxRoot = "C:\tools\nginx-$versionElegida"
        
        Write-Info "Extrayendo a: $nginxRoot..."
        
        # Crear directorio si no existe
        if (Test-Path $nginxRoot) {
            Write-Warn "Eliminando instalacion anterior..."
            Remove-Item -Path $nginxRoot -Recurse -Force
        }
        New-Item -ItemType Directory -Path $nginxRoot -Force | Out-Null
        
        # Extraer ZIP
        try {
            Expand-Archive -Path $archivoLocal -DestinationPath "C:\tools" -Force
            
            # Buscar la carpeta extraída
            $extractedFolders = Get-ChildItem -Path "C:\tools" -Directory | Where-Object { $_.Name -match '^nginx' }
            if ($extractedFolders) {
                $extractedFolder = $extractedFolders[0].FullName
                if ($extractedFolder -ne $nginxRoot) {
                    Move-Item -Path "$extractedFolder\*" -Destination $nginxRoot -Force
                    Remove-Item -Path $extractedFolder -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            
            Write-Ok "Nginx extraido correctamente"
        } catch {
            Write-Err "Error al extraer: $_"
            return
        }
        
    } else {
        # Instalación desde WEB (Chocolatey)
        Asegurar-Chocolatey

        Write-Info "Consultando versiones disponibles de Nginx..."
        $rawVersiones = choco search nginx --exact --all-versions --limit-output 2>$null
        $versiones = @()
        foreach ($linea in $rawVersiones) {
            if ($linea -match '\|') {
                $ver = ($linea -split '\|')[1].Trim()
                if ($ver -match '^\d+\.\d+' -and $versiones -notcontains $ver) { $versiones += $ver }
            }
        }
        if ($versiones.Count -eq 0) { Write-Err "No se encontraron versiones de Nginx."; return }

        $mainline = $versiones | Where-Object {
            $p = $_ -split '\.'; $p.Count -ge 2 -and ([int]$p[1] % 2 -ne 0)
        } | Select-Object -First 1
        $stable = $versiones | Where-Object {
            $p = $_ -split '\.'; $p.Count -ge 2 -and ([int]$p[1] % 2 -eq 0)
        } | Select-Object -First 1
        if (-not $mainline) { $mainline = $versiones[0] }
        if (-not $stable)   { $stable   = if ($versiones.Count -ge 2) { $versiones[1] } else { $versiones[0] } }

        Write-Host ""
        Write-Host "Versiones disponibles:" -ForegroundColor Cyan
        Write-Host "  1. $mainline  [Mainline - Desarrollo]"
        Write-Host "  2. $stable    [Stable - LTS]"
        Write-Host ""
        do { $selVer = Read-Host "Selecciona version (1/2)" } while ($selVer -notmatch '^[12]$')
        $versionElegida = if ($selVer -eq "1") { $mainline } else { $stable }

        Write-Info "Instalando Nginx $versionElegida..."
        choco install nginx --version="$versionElegida" --yes --no-progress --force 2>&1 | Out-Null
        Refrescar-Path

        # Verificar que nginx.exe exista
        $nginxRootCheck = Obtener-Ruta-Nginx
        if (-not $nginxRootCheck) {
            Write-Err "No se encontro nginx.exe. Verifica la instalacion de Chocolatey."
            Write-Info "Intenta manualmente: choco install nginx --version=$versionElegida --force"
            return
        }
        Write-Ok "Nginx $versionElegida disponible en: $nginxRootCheck"
        $nginxRoot = $nginxRootCheck
    }

    if (-not (Get-Command nssm -ErrorAction SilentlyContinue)) {
        Write-Info "Instalando NSSM..."
        choco install nssm --yes --no-progress 2>&1 | Out-Null
        Refrescar-Path
    }

    $nginxRoot = Obtener-Ruta-Nginx
    if (-not $nginxRoot) { Write-Err "No se encontro nginx.exe tras la instalacion."; return }
    Write-Info "Nginx encontrado en: $nginxRoot"

    $nginxConf = "$nginxRoot\conf\nginx.conf"
    # Escribir nginx.conf completo sin BOM (BOM causa "unknown directive" en nginx)
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $nginxConfContent = @"
worker_processes  1;

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    server_tokens off;

    sendfile        on;
    keepalive_timeout  65;

    server {
        listen       $puerto;
        server_name  localhost;

        add_header X-Frame-Options SAMEORIGIN always;
        add_header X-Content-Type-Options nosniff always;

        location / {
            root   html;
            index  index.html index.htm;
            autoindex off;
        }

        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   html;
        }
    }
}
"@
    [System.IO.File]::WriteAllText($nginxConf, $nginxConfContent, $utf8NoBom)
    Write-Ok "nginx.conf escrito sin BOM, puerto $puerto configurado."

    crearHTML -rutaWeb "$nginxRoot\html" -servicio "Nginx" -version $versionElegida -puerto $puerto
    configurarFirewall -puertoNuevo $puerto -puertoViejo 80 -nombreServicio "Nginx"

    $serviceName = "nginx-$puerto"
    $nginxExe    = "$nginxRoot\nginx.exe"
    $svcAnterior = Get-Service $serviceName -ErrorAction SilentlyContinue
    if ($svcAnterior) {
        Stop-Service $serviceName -Force -ErrorAction SilentlyContinue
        & nssm remove $serviceName confirm 2>&1 | Out-Null
    }
    & nssm install $serviceName $nginxExe 2>&1 | Out-Null
    & nssm set     $serviceName AppDirectory $nginxRoot 2>&1 | Out-Null
    & nssm set     $serviceName DisplayName "Nginx HTTP Server (puerto $puerto)" 2>&1 | Out-Null
    & nssm set     $serviceName Start SERVICE_AUTO_START 2>&1 | Out-Null
    & nssm set     $serviceName AppStdout "$nginxRoot\logs\service.log" 2>&1 | Out-Null
    & nssm set     $serviceName AppStderr "$nginxRoot\logs\service-error.log" 2>&1 | Out-Null

    Start-Service $serviceName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    $svc = Get-Service $serviceName -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Write-Ok "Nginx activo en puerto $puerto (servicio: $serviceName)"
    } else {
        Write-Err "Nginx no arranco. Revisa: $nginxRoot\logs\error.log"
        Write-Info "O inicia manualmente: nssm start $serviceName"
    }
}

# =============== INSTALAR HTTP (menu interno) ===============
function InstalarHTTP {
    Clear-Host
    Write-Host ""
    Write-Host "------------------------------------------------" -ForegroundColor Blue
    Write-Host "         INSTALACION DE SERVIDOR HTTP           " -ForegroundColor Blue
    Write-Host "------------------------------------------------" -ForegroundColor Blue
    Write-Host "  1. IIS  (nativo Windows)"
    Write-Host "  2. Apache HTTP Server"
    Write-Host "  3. Nginx"
    Write-Host "  0. Volver"
    Write-Host "------------------------------------------------" -ForegroundColor Blue
    Write-Host ""
    $s = Read-Host "Servidor"
    if ($s -eq "0") { return }
    if ($s -notin @("1","2","3")) { Write-Warn "Opcion no valida."; return }
    $puerto = pedirPuerto -default 80
    switch ($s) {
        "1" { instalarIIS    -puerto $puerto }
        "2" { instalarApache -puerto $puerto }
        "3" { instalarNginx  -puerto $puerto }
    }
}

# =============== VERIFICAR ESTADO ===============
function VerificarHTTP {
    Clear-Host
    Write-Host ""
    Write-Host "=== Estado de Servidores HTTP ===" -ForegroundColor Blue
    Write-Host ""

    Write-Host -NoNewline "  IIS     : "
    $iis = Get-Service W3SVC -ErrorAction SilentlyContinue
    if ($iis) {
        $ver    = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\InetStp" -ErrorAction SilentlyContinue).VersionString
        $appcmd = "$env:SystemRoot\system32\inetsrv\appcmd.exe"
        $puerto = & $appcmd list site "Default Web Site" 2>$null |
            Select-String ':(\d+):' | ForEach-Object { $_.Matches[0].Groups[1].Value } | Select-Object -First 1
        if ($iis.Status -eq "Running") {
            Write-Host "Activo -- version: $ver -- puerto: $puerto" -ForegroundColor Green
        } else { Write-Host "Detenido -- version: $ver" -ForegroundColor Yellow }
    } else { Write-Host "No instalado" -ForegroundColor Red }

    Write-Host -NoNewline "  Apache2 : "
    $apache = Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "^Apache" } | Select-Object -First 1
    if ($apache) {
        $apacheRoot = @("C:\Apache24","$env:APPDATA\Apache24") |
            Where-Object { Test-Path "$_\conf\httpd.conf" } | Select-Object -First 1
        $puerto = if ($apacheRoot) {
            Get-Content "$apacheRoot\conf\httpd.conf" |
                Select-String '^Listen\s+(\d+)' |
                ForEach-Object { $_.Matches[0].Groups[1].Value } | Select-Object -First 1
        } else { "?" }
        if ($apache.Status -eq "Running") {
            Write-Host "Activo -- puerto: $puerto" -ForegroundColor Green
        } else { Write-Host "Detenido -- puerto: $puerto" -ForegroundColor Yellow }
    } else { Write-Host "No instalado" -ForegroundColor Red }

    Write-Host -NoNewline "  Nginx   : "
    $nginx = Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "^nginx" } | Select-Object -First 1
    if ($nginx) {
        $nginxRoot = Obtener-Ruta-Nginx
        $puerto = if ($nginxRoot -and (Test-Path "$nginxRoot\conf\nginx.conf")) {
            Get-Content "$nginxRoot\conf\nginx.conf" |
                Select-String 'listen\s+(\d+)' |
                ForEach-Object { $_.Matches[0].Groups[1].Value } | Select-Object -First 1
        } else { "?" }
        if ($nginx.Status -eq "Running") {
            Write-Host "Activo -- puerto: $puerto (servicio: $($nginx.Name))" -ForegroundColor Green
        } else { Write-Host "Detenido -- puerto: $puerto" -ForegroundColor Yellow }
    } else { Write-Host "No instalado" -ForegroundColor Red }

    Write-Host ""
}

# =============== REVISAR HTTP ===============
function RevisarHTTP {
    Clear-Host
    Write-Host ""
    Write-Host "=== Revision de Servidores HTTP ===" -ForegroundColor Blue
    Write-Host ""
    Write-Host "  [1] IIS"
    Write-Host "  [2] Apache2"
    Write-Host "  [3] Nginx"
    Write-Host "  [4] Todos"
    Write-Host ""
    $opcion = Read-Host "Selecciona [1-4]"
    if ($opcion -notmatch '^[1234]$') { Write-Warn "Opcion invalida."; return }

    function Curl-Servidor {
        param([string]$nombre, [int]$puerto)
        Write-Host ""
        Write-Host "--- $nombre (puerto $puerto) ---" -ForegroundColor Blue
        Write-Host "Headers:" -ForegroundColor Cyan
        try {
            $resp = Invoke-WebRequest -Uri "http://localhost:$puerto" -Method Head -UseBasicParsing -ErrorAction Stop
            $resp.Headers.GetEnumerator() | ForEach-Object { Write-Host "  $($_.Key): $($_.Value)" }
        } catch { Write-Err "Sin respuesta en puerto $puerto" }
        Write-Host "Index:" -ForegroundColor Cyan
        try {
            $resp = Invoke-WebRequest -Uri "http://localhost:$puerto" -UseBasicParsing -ErrorAction Stop
            Write-Host $resp.Content
        } catch { Write-Err "No se pudo obtener index de puerto $puerto" }
    }

    $appcmd = "$env:SystemRoot\system32\inetsrv\appcmd.exe"
    $puertoIIS = if (Test-Path $appcmd) {
        & $appcmd list site "Default Web Site" 2>$null |
            Select-String ':(\d+):' | ForEach-Object { $_.Matches[0].Groups[1].Value } | Select-Object -First 1
    } else { 80 }

    $apacheRoot   = @("C:\Apache24","$env:APPDATA\Apache24") |
        Where-Object { Test-Path "$_\conf\httpd.conf" } | Select-Object -First 1
    $puertoApache = if ($apacheRoot) {
        Get-Content "$apacheRoot\conf\httpd.conf" |
            Select-String '^Listen\s+(\d+)' |
            ForEach-Object { $_.Matches[0].Groups[1].Value } | Select-Object -First 1
    } else { 80 }

    $nginxRoot    = Obtener-Ruta-Nginx
    $puertoNginx  = if ($nginxRoot -and (Test-Path "$nginxRoot\conf\nginx.conf")) {
        Get-Content "$nginxRoot\conf\nginx.conf" |
            Select-String 'listen\s+(\d+)' |
            ForEach-Object { $_.Matches[0].Groups[1].Value } | Select-Object -First 1
    } else { 80 }

    switch ($opcion) {
        "1" { Curl-Servidor "IIS"    ([int]$puertoIIS)    }
        "2" { Curl-Servidor "Apache" ([int]$puertoApache) }
        "3" { Curl-Servidor "Nginx"  ([int]$puertoNginx)  }
        "4" {
            Curl-Servidor "IIS"    ([int]$puertoIIS)
            Curl-Servidor "Apache" ([int]$puertoApache)
            Curl-Servidor "Nginx"  ([int]$puertoNginx)
        }
    }
}


$FTP_SERVER   = "10.214.43.70"
$FTP_USER     = "ftprepo"
$FTP_PASS     = "Repo123!"
$FTP_BASE_PATH = "/http/Windows"
$TMP_DIR      = "$env:TEMP\practica7"
$SSL_DIR      = "C:\SSL\practica7"
$SERVICIO_ACTUAL     = ""
$FUENTE_INSTALACION  = ""
$CONFIGURAR_SSL      = $false
$PUERTO_ELEGIDO      = 0
$ARCHIVO_DESCARGADO  = ""

function Preparar-Entorno {
    if (-not (Test-Path $TMP_DIR)) {
        New-Item -ItemType Directory -Path $TMP_DIR -Force | Out-Null
    }
    if (-not (Test-Path $SSL_DIR)) {
        New-Item -ItemType Directory -Path "$SSL_DIR\certs"   -Force | Out-Null
        New-Item -ItemType Directory -Path "$SSL_DIR\private" -Force | Out-Null
    }
}

function Menu-Principal {
    Clear-Host
    Write-Title "========================================================"
    Write-Title "  Practica 7 - Instalacion Hibrida con SSL/TLS"
    Write-Title "========================================================"
    Write-Host ""
    Write-Info "Seleccione el servicio a instalar:"
    Write-Host "  [1] IIS"
    Write-Host "  [2] Apache HTTP Server"
    Write-Host "  [3] Nginx"
    Write-Host "  [0] Salir"
    Write-Host ""

    do {
        $opcion = Read-Host "Opcion"
    } while ($opcion -notmatch '^[0-3]$')

    switch ($opcion) {
        "1" { $script:SERVICIO_ACTUAL = "IIS"    }
        "2" { $script:SERVICIO_ACTUAL = "Apache" }
        "3" { $script:SERVICIO_ACTUAL = "Nginx"  }
        "0" { exit 0 }
    }
}

function Seleccionar-Fuente {
    # IIS no requiere fuente externa - siempre se instala desde Windows
    if ($SERVICIO_ACTUAL -eq "IIS") {
        $script:FUENTE_INSTALACION = "WINDOWS"
        Write-Info "IIS se instala directamente desde las caracteristicas de Windows."
        return
    }

    Write-Host ""
    Write-Info "Desde donde desea instalar $SERVICIO_ACTUAL?"
    Write-Host "  [W] WEB - Chocolatey/Repositorios oficiales"
    Write-Host "  [F] FTP - Repositorio privado"
    Write-Host ""

    do {
        $fuente = Read-Host "Seleccione [W/F]"
    } while ($fuente -notmatch '^[WwFf]$')

    $script:FUENTE_INSTALACION = if ($fuente -match '^[Ww]$') { "WEB" } else { "FTP" }
}

function Descargar-DesdeFTP {
    param([string]$servicio)

    Write-Title "Conectando al Repositorio FTP"

    # Las carpetas en el FTP tienen mayuscula inicial: Apache, Nginx, IIS
    $ftpPath = "$FTP_BASE_PATH/$servicio/"

    try {
        # Nota: [array] evita que PowerShell desenvuelva un array de un elemento como string
        [array]$archivosDisponibles = switch ($servicio) {
            "Nginx"  { @("nginx-1.22.1.zip", "nginx-1.24.0.zip") }
            "Apache" { @("httpd-2.4.66-260223-Win64-VS18.zip")   }
            "IIS"    { @() }  # IIS se instala desde Windows, no desde FTP
            default  { @() }
        }

        if ($archivosDisponibles.Count -eq 0) {
            Write-Err "No hay archivos configurados para $servicio"
            return $null
        }

        Write-Ok "Versiones disponibles:"
        for ($i = 0; $i -lt $archivosDisponibles.Count; $i++) {
            Write-Host "  [$($i+1)] $($archivosDisponibles[$i])"
        }
        Write-Host ""

        do {
            $seleccion = Read-Host "Seleccione version [1-$($archivosDisponibles.Count)]"
        } while ($seleccion -notmatch '^\d+$' -or [int]$seleccion -lt 1 -or [int]$seleccion -gt $archivosDisponibles.Count)

        $archivoElegido = $archivosDisponibles[[int]$seleccion - 1]
        Write-Ok "Seleccionado: $archivoElegido"

        $localFile   = Join-Path $TMP_DIR $archivoElegido
        $downloadUrl = "ftp://$FTP_SERVER$ftpPath$archivoElegido"

        Write-Info "Descargando $archivoElegido desde ftp://$FTP_SERVER$ftpPath ..."

        $webClient = New-Object System.Net.WebClient
        $webClient.Credentials = New-Object System.Net.NetworkCredential($FTP_USER, $FTP_PASS)

        $global:downloadComplete = $false
        $global:downloadError    = $null

        Register-ObjectEvent -InputObject $webClient -EventName DownloadProgressChanged `
            -SourceIdentifier WebClient.DownloadProgressChanged -Action {
                Write-Progress -Activity "Descargando archivo" `
                    -Status "$($EventArgs.ProgressPercentage)% completado" `
                    -PercentComplete $EventArgs.ProgressPercentage
            } | Out-Null

        Register-ObjectEvent -InputObject $webClient -EventName DownloadFileCompleted `
            -SourceIdentifier WebClient.DownloadFileCompleted -Action {
                if ($EventArgs.Error) { $global:downloadError = $EventArgs.Error.Message }
                $global:downloadComplete = $true
            } | Out-Null

        $webClient.DownloadFileAsync([Uri]$downloadUrl, $localFile)
        while (-not $global:downloadComplete) { Start-Sleep -Milliseconds 100 }

        Unregister-Event -SourceIdentifier WebClient.DownloadProgressChanged -ErrorAction SilentlyContinue
        Unregister-Event -SourceIdentifier WebClient.DownloadFileCompleted    -ErrorAction SilentlyContinue
        $webClient.Dispose()
        Write-Progress -Activity "Descargando archivo" -Completed

        if ($global:downloadError) {
            Write-Err "Error durante la descarga: $($global:downloadError)"
            return $null
        }

        if (-not (Test-Path $localFile)) {
            Write-Err "El archivo no se descargo (no existe en disco)"
            return $null
        }

        $fileSize = (Get-Item $localFile).Length
        Write-Ok "Descarga completa ($([math]::Round($fileSize/1MB, 2)) MB)"

        try {
            $hashUrl  = "ftp://$FTP_SERVER$ftpPath$archivoElegido.sha256"
            $hashFile = "$localFile.sha256"
            Write-Info "Descargando hash SHA256..."
            $hashClient = New-Object System.Net.WebClient
            $hashClient.Credentials = New-Object System.Net.NetworkCredential($FTP_USER, $FTP_PASS)
            $hashClient.DownloadFile($hashUrl, $hashFile)
            $hashClient.Dispose()
            Write-Title "Verificando Integridad"
            $hashCalc = (Get-FileHash -Path $localFile -Algorithm SHA256).Hash.ToLower()
            $hashEsp  = (Get-Content $hashFile -Raw).Split()[0].Trim().ToLower()
            if ($hashCalc -eq $hashEsp) {
                Write-Ok "Archivo integro (hash verificado)"
            } else {
                Write-Err "Hash no coincide. Archivo posiblemente corrompido."
                return $null
            }
        } catch {
            Write-Warn "No se encontro archivo .sha256 en el FTP, omitiendo verificacion."
        }

        return $localFile

    } catch {
        Write-Err "Error FTP: $($_.Exception.Message)"
        return $null
    }
}


# =============== CONFIGURAR SSL (OpenSSL) ===============
function Configurar-SSL {
    param(
        [string]$servicio,
        [int]$puertoHTTP,
        [string]$apacheRoot = "C:\Apache24",
        [string]$nginxRoot  = ""
    )

    $puertoHTTPS = $puertoHTTP + 1
    Write-Title "Configurando SSL/TLS (HTTPS en puerto $puertoHTTPS)"

    # ── 1. Asegurar OpenSSL ───────────────────────────────────────────────────
    $opensslExe = $null
    # Buscar openssl.exe en rutas conocidas
    $candidatos = @(
        "$apacheRoot\bin\openssl.exe",
        "C:\Program Files\OpenSSL-Win64\bin\openssl.exe",
        "C:\Program Files (x86)\OpenSSL-Win32\bin\openssl.exe",
        "C:\tools\openssl\openssl.exe"
    )
    foreach ($c in $candidatos) {
        if (Test-Path $c) { $opensslExe = $c; break }
    }
    if (-not $opensslExe) {
        $found = Get-Command openssl -ErrorAction SilentlyContinue
        if ($found) { $opensslExe = $found.Source }
    }
    if (-not $opensslExe) {
        Write-Info "OpenSSL no encontrado. Instalando via Chocolatey..."
        choco install openssl --yes --no-progress 2>&1 | Out-Null
        Refrescar-Path
        $found = Get-Command openssl -ErrorAction SilentlyContinue
        if ($found) {
            $opensslExe = $found.Source
            Write-Ok "OpenSSL instalado: $opensslExe"
        } else {
            Write-Err "No se pudo instalar OpenSSL. SSL cancelado."
            return
        }
    } else {
        Write-Ok "OpenSSL encontrado: $opensslExe"
    }

    # ── 2. Directorios de certificados ───────────────────────────────────────
    $certDir = "$SSL_DIR\certs"
    $keyDir  = "$SSL_DIR\private"
    if (-not (Test-Path $certDir))  { New-Item -ItemType Directory -Path $certDir  -Force | Out-Null }
    if (-not (Test-Path $keyDir))   { New-Item -ItemType Directory -Path $keyDir   -Force | Out-Null }

    $keyFile  = "$keyDir\server.key"
    $certFile = "$certDir\server.crt"
    $csrFile  = "$certDir\server.csr"
    $cnfFile  = "$certDir\openssl.cnf"

    # ── 3. Generar openssl.cnf con SAN ───────────────────────────────────────
    Write-Info "Generando configuracion OpenSSL..."
    $hostname = $env:COMPUTERNAME
    $cnfContent = @"
[req]
default_bits       = 2048
prompt             = no
default_md         = sha256
distinguished_name = dn
x509_extensions    = v3_req

[dn]
C  = MX
ST = Estado
L  = Ciudad
O  = Practica7
OU = SysAdmin
CN = $hostname

[v3_req]
subjectAltName = @alt_names
keyUsage       = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth

[alt_names]
DNS.1 = localhost
DNS.2 = $hostname
IP.1  = 127.0.0.1
"@
    [System.IO.File]::WriteAllText($cnfFile, $cnfContent, (New-Object System.Text.UTF8Encoding $false))

    # ── 4. Generar clave privada y certificado autofirmado ───────────────────
    Write-Info "Generando clave privada (2048 bits)..."
    & $opensslExe genrsa -out $keyFile 2048 2>&1 | Out-Null
    if (-not (Test-Path $keyFile)) { Write-Err "Error generando clave privada."; return }
    Write-Ok "Clave privada generada: $keyFile"

    Write-Info "Generando certificado autofirmado (365 dias)..."
    & $opensslExe req -new -x509 -key $keyFile -out $certFile -days 365 -config $cnfFile 2>&1 | Out-Null
    if (-not (Test-Path $certFile)) { Write-Err "Error generando certificado."; return }
    Write-Ok "Certificado generado: $certFile"

    # ── 5. Configurar el servidor ─────────────────────────────────────────────
    switch ($servicio) {

        "Apache" {
            $httpdConf = "$apacheRoot\conf\httpd.conf"

            # Activar modulos SSL si estan comentados
            # Se usa UTF8 sin BOM para no corromper httpd.conf
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            $conf = [System.IO.File]::ReadAllText($httpdConf)
            $conf = $conf -replace '# *(LoadModule ssl_module)',           '$1'
            $conf = $conf -replace '# *(LoadModule socache_shmcb_module)', '$1'
            $conf = $conf -replace '# *(Include conf/extra/httpd-ssl\.conf)', '$1'
            [System.IO.File]::WriteAllText($httpdConf, $conf, $utf8NoBom)

            # Verificar que los modulos quedaron activos
            $confCheck = [System.IO.File]::ReadAllText($httpdConf)
            $sslMod    = $confCheck -match 'LoadModule ssl_module'
            $shmcbMod  = $confCheck -match 'LoadModule socache_shmcb_module'
            $sslInc    = $confCheck -match 'Include conf/extra/httpd-ssl\.conf'
            if ($sslMod -and $shmcbMod -and $sslInc) {
                Write-Ok "Modulos SSL activados en httpd.conf"
            } else {
                Write-Warn "No se pudieron activar todos los modulos SSL automaticamente."
                Write-Info "Verifica manualmente en httpd.conf:"
                Write-Info "  LoadModule ssl_module modules/mod_ssl.so"
                Write-Info "  LoadModule socache_shmcb_module modules/mod_socache_shmcb.so"
                Write-Info "  Include conf/extra/httpd-ssl.conf"
            }

            # Escribir httpd-ssl.conf
            $sslConf = "$apacheRoot\conf\extra\httpd-ssl.conf"
            $sslContent = @"
Listen $puertoHTTPS

SSLCipherSuite HIGH:MEDIUM:!MD5:!RC4:!3DES
SSLProxyCipherSuite HIGH:MEDIUM:!MD5:!RC4:!3DES
SSLHonorCipherOrder on
SSLProtocol all -SSLv3
SSLProxyProtocol all -SSLv3
SSLPassPhraseDialog  builtin
SSLSessionCache        "shmcb:`${SRVROOT}/logs/ssl_scache(512000)"
SSLSessionCacheTimeout  300

<VirtualHost _default_:$puertoHTTPS>
    DocumentRoot "`${SRVROOT}/htdocs"
    ServerName localhost:$puertoHTTPS
    ErrorLog "`${SRVROOT}/logs/error_ssl.log"
    TransferLog "`${SRVROOT}/logs/access_ssl.log"
    SSLEngine on
    SSLCertificateFile    "$certFile"
    SSLCertificateKeyFile "$keyFile"
    <FilesMatch "\.(cgi|shtml|phtml|php)$">
        SSLOptions +StdEnvVars
    </FilesMatch>
    <Directory "`${SRVROOT}/cgi-bin">
        SSLOptions +StdEnvVars
    </Directory>
    BrowserMatch "MSIE [2-5]" nokeepalive ssl-unclean-shutdown downgrade-1.0 force-response-1.0
</VirtualHost>
"@
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::WriteAllText($sslConf, $sslContent, $utf8NoBom)
            Write-Ok "httpd-ssl.conf configurado (puerto HTTPS: $puertoHTTPS)"

            # Validar y reiniciar
            $test = & "$apacheRoot\bin\httpd.exe" -t 2>&1
            if ($test -match "Syntax OK") {
                Write-Ok "Configuracion valida."
                Restart-Service Apache2.4 -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 3
                $svc = Get-Service Apache2.4 -ErrorAction SilentlyContinue
                if ($svc -and $svc.Status -eq "Running") {
                    Write-Ok "Apache reiniciado con SSL activo"
                } else {
                    Write-Err "Apache no arranco tras activar SSL. Revisa: $apacheRoot\logs\error_ssl.log"
                }
            } else {
                Write-Err "Error en configuracion SSL:"
                Write-Host $test -ForegroundColor Red
            }

            configurarFirewall -puertoNuevo $puertoHTTPS -puertoViejo 0 -nombreServicio "Apache-SSL"
        }

        "Nginx" {
            if (-not $nginxRoot) { $nginxRoot = Obtener-Ruta-Nginx }
            if (-not $nginxRoot) { Write-Err "No se encontro Nginx."; return }

            $nginxConf = "$nginxRoot\conf\nginx.conf"
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false

            # Rutas con forward slash para nginx.conf
            $certFwd = $certFile.Replace('\', '/')
            $keyFwd  = $keyFile.Replace('\', '/')

            $nginxConfContent = @"
worker_processes  1;

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    server_tokens off;
    sendfile        on;
    keepalive_timeout  65;

    # HTTP - redirige a HTTPS
    server {
        listen       $puertoHTTP;
        server_name  localhost;
        return 301 https://`$host:$puertoHTTPS`$request_uri;
    }

    # HTTPS
    server {
        listen       $puertoHTTPS ssl;
        server_name  localhost;

        ssl_certificate     $certFwd;
        ssl_certificate_key $keyFwd;
        ssl_protocols       TLSv1.2 TLSv1.3;
        ssl_ciphers         HIGH:!aNULL:!MD5;
        ssl_session_cache   shared:SSL:10m;
        ssl_session_timeout 10m;

        add_header X-Frame-Options SAMEORIGIN always;
        add_header X-Content-Type-Options nosniff always;
        add_header Strict-Transport-Security "max-age=31536000" always;

        location / {
            root   html;
            index  index.html index.htm;
            autoindex off;
        }

        error_page 500 502 503 504 /50x.html;
        location = /50x.html { root html; }
    }
}
"@
            [System.IO.File]::WriteAllText($nginxConf, $nginxConfContent, $utf8NoBom)
            Write-Ok "nginx.conf actualizado con SSL (HTTP:$puertoHTTP -> HTTPS:$puertoHTTPS)"

            # Reiniciar servicio nginx
            $serviceName = "nginx-$puertoHTTP"
            Restart-Service $serviceName -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
            $svc = Get-Service $serviceName -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -eq "Running") {
                Write-Ok "Nginx reiniciado con SSL activo"
            } else {
                Write-Err "Nginx no arranco tras activar SSL."
                Write-Info "Revisa: $nginxRoot\logs\error.log"
            }

            configurarFirewall -puertoNuevo $puertoHTTPS -puertoViejo 0 -nombreServicio "Nginx-SSL"
        }

        "IIS" {
            Write-Info "IIS: Preparando certificado PFX con clave privada..."

            $pfxFile = "$SSL_DIR\certs\server.pfx"
            $pfxPass = "practica7ssl"

            # Combinar .crt + .key en un .pfx usando OpenSSL
            & $opensslExe pkcs12 -export `
                -out $pfxFile `
                -inkey $keyFile `
                -in $certFile `
                -passout pass:$pfxPass 2>&1 | Out-Null

            if (-not (Test-Path $pfxFile)) {
                Write-Err "No se pudo generar el archivo PFX."
                return
            }
            Write-Ok "PFX generado: $pfxFile"

            # Importar PFX al store LocalMachine\My (incluye clave privada)
            Write-Info "Importando PFX al store de Windows..."
            $secPass = ConvertTo-SecureString $pfxPass -AsPlainText -Force
            $cert = Import-PfxCertificate `
                -FilePath $pfxFile `
                -CertStoreLocation Cert:\LocalMachine\My `
                -Password $secPass `
                -ErrorAction Stop

            if (-not $cert) {
                Write-Err "No se pudo importar el PFX."
                return
            }
            Write-Ok "Certificado importado. Thumbprint: $($cert.Thumbprint)"

            # Agregar binding HTTPS usando WebAdministration
            Import-Module WebAdministration -ErrorAction Stop

            # Verificar que el certificado fue importado correctamente
            Write-Info "Buscando certificado en store..."
            $cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -match "Practica7" } | Select-Object -First 1
            if (-not $cert) {
                Write-Err "Certificado no encontrado en Cert:\LocalMachine\My"
                Write-Info "Certificados disponibles:"
                Get-ChildItem Cert:\LocalMachine\My | ForEach-Object { Write-Host "  $($_.Subject) [$($_.Thumbprint)]" }
                return
            }
            Write-Ok "Certificado encontrado. Thumbprint: $($cert.Thumbprint)"

            # Eliminar binding anterior si existe
            $bindingExistente = Get-WebBinding -Name "Default Web Site" -Protocol https -Port $puertoHTTPS -ErrorAction SilentlyContinue
            if ($bindingExistente) {
                Write-Info "Eliminando binding HTTPS anterior..."
                Remove-WebBinding -Name "Default Web Site" -Protocol https -Port $puertoHTTPS
            }

            # Crear el binding HTTPS
            Write-Info "Creando binding HTTPS en puerto $puertoHTTPS..."
            New-WebBinding -Name "Default Web Site" -Protocol https -Port $puertoHTTPS -IPAddress "*"
            Write-Ok "Binding HTTPS creado"

            # Asignar certificado al binding
            Write-Info "Asignando certificado al binding..."
            $binding = Get-WebBinding -Name "Default Web Site" -Protocol https -Port $puertoHTTPS
            if (-not $binding) {
                Write-Err "No se pudo obtener el binding HTTPS recien creado"
                return
            }
            $binding.AddSslCertificate($cert.Thumbprint, "My")
            Write-Ok "Certificado asignado al binding HTTPS"

            # Verificar binding final
            $bindingFinal = Get-WebBinding -Name "Default Web Site"
            Write-Info "Bindings activos:"
            $bindingFinal | ForEach-Object { Write-Host "  $($_.protocol)://*:$($_.bindingInformation)" -ForegroundColor Cyan }

            # Eliminar sslcert anterior si existe y registrar el nuevo
            & netsh http delete sslcert ipport=0.0.0.0:$puertoHTTPS 2>&1 | Out-Null
            $appId = "{$(New-Guid)}"
            $result = & netsh http add sslcert ipport=0.0.0.0:$puertoHTTPS `
                certhash=$($cert.Thumbprint) `
                appid="$appId" 2>&1
            if ($result -match "SSL Certificate successfully added") {
                Write-Ok "Certificado SSL registrado en netsh"
            } else {
                Write-Warn "netsh output: $result"
            }

            configurarFirewall -puertoNuevo $puertoHTTPS -puertoViejo 0 -nombreServicio "IIS-SSL"

            # Reiniciar IIS
            Write-Info "Reiniciando IIS..."
            & iisreset /noforce 2>&1 | Out-Null
            Start-Sleep -Seconds 3

            # Verificar que responde en HTTPS
            try {
                $resp = Invoke-WebRequest -Uri "https://localhost:$puertoHTTPS" `
                    -UseBasicParsing -SkipCertificateCheck -ErrorAction Stop
                Write-Ok "IIS respondiendo en https://localhost:$puertoHTTPS"
            } catch {
                Write-Warn "IIS no respondio en HTTPS aun. Puede tardar unos segundos."
                Write-Info "Prueba manualmente: https://localhost:$puertoHTTPS"
            }
        }
    }

    Write-Ok "SSL/TLS configurado correctamente"
    Write-Info "HTTP  : http://localhost:$puertoHTTP"
    Write-Info "HTTPS : https://localhost:$puertoHTTPS"
    Write-Warn "El certificado es autofirmado. El navegador mostrara advertencia de seguridad (esperado)."
}

# ── Verificar Administrador ───────────────────────────────────────────────────
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[x] Este script debe ejecutarse como Administrador." -ForegroundColor Red
    exit 1
}

# ── Flujo principal ───────────────────────────────────────────────────────────
Asegurar-Chocolatey
Preparar-Entorno
Menu-Principal
Seleccionar-Fuente

Write-Host ""
$sslResp = Read-Host "Desea activar SSL/TLS? [S/N]"
$script:CONFIGURAR_SSL = $sslResp -match '^[SsYy]$'

if ($FUENTE_INSTALACION -eq "FTP" -and $SERVICIO_ACTUAL -ne "IIS") {
    $script:ARCHIVO_DESCARGADO = Descargar-DesdeFTP -servicio $SERVICIO_ACTUAL
    if (-not $ARCHIVO_DESCARGADO) {
        Write-Host "[x] Descarga FTP fallida. Verifique conexion y credenciales." -ForegroundColor Red
        Write-Host "[i] Servidor : ftp://$FTP_SERVER" -ForegroundColor Cyan
        Write-Host "[i] Usuario  : $FTP_USER"         -ForegroundColor Cyan
        Write-Host "[i] Ruta base: $FTP_BASE_PATH"    -ForegroundColor Cyan
        exit 1
    }
} elseif ($SERVICIO_ACTUAL -eq "IIS") {
    Write-Host "[i] IIS se instala desde Windows directamente (no requiere descarga FTP)." -ForegroundColor Cyan
}

$script:PUERTO_ELEGIDO = pedirPuerto -default 80

switch ($SERVICIO_ACTUAL) {
    "IIS" {
        instalarIIS -puerto $PUERTO_ELEGIDO
        if ($CONFIGURAR_SSL) {
            Configurar-SSL -servicio "IIS" -puertoHTTP $PUERTO_ELEGIDO
        }
    }
    "Apache" {
        if ($ARCHIVO_DESCARGADO) {
            instalarApache -puerto $PUERTO_ELEGIDO -archivoLocal $ARCHIVO_DESCARGADO
        } else {
            instalarApache -puerto $PUERTO_ELEGIDO
        }
        if ($CONFIGURAR_SSL) {
            Configurar-SSL -servicio "Apache" -puertoHTTP $PUERTO_ELEGIDO -apacheRoot "C:\Apache24"
        }
    }
    "Nginx" {
        if ($ARCHIVO_DESCARGADO) {
            instalarNginx -puerto $PUERTO_ELEGIDO -archivoLocal $ARCHIVO_DESCARGADO
        } else {
            instalarNginx -puerto $PUERTO_ELEGIDO
        }
        if ($CONFIGURAR_SSL) {
            Configurar-SSL -servicio "Nginx" -puertoHTTP $PUERTO_ELEGIDO
        }
    }
}

Write-Ok "========================================================"
Write-Ok "  Instalacion Completada"
Write-Ok "========================================================"