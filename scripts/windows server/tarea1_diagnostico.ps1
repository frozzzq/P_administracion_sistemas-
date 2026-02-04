write-host '===================================================================' -foregroundcolor cyan
write-host '====================DIAGNOSTICO DE WINDOWS SERVER.=================' -foregroundcolor blue
write-host '===================================================================' -foregroundcolor cyan
write-host "nombre del equipo	: $env:COMPUTERNAME"
write-host "fecha y hora	: $(get-date)"

$ip = get-netipaddress -addressfamily ipv4 | where-object { $_.interfacealias -like "*Ethernet 2*" -and $_.IPAddress -notlike "169.254*"} | select-object -first 1
write-host "IP actual		" -nonewline; write-host $ip.ipaddress -foregroundcolor yellow

$diskC = get-ciminstance win32_logicaldisk | where-object { $_.deviceid -eq "C:" }
$free = [math]::round($diskC.FreeSpace / 1GB, 2)
$total = [math]::round($diskC.size /1GB, 2)
write-host "espacio en disco:  " -nonewline; write-host "$free GB disponibles de $total GB" -foregroundcolor yellow

write-host '===================================================================' -foregroundcolor cyan



