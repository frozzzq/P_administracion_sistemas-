Write Host "======================================================================" -ForegroundColor Yellow
Write Host "                           SERVIDOR DNS                               "
Write Host "======================================================================" -ForegroundColor Yellow


do{
    write host "[1] - VERIFICAR INSTALACION DNS"
    write host "[2] - INSTALAR SERVICIO DNS"
    write host "[3] - REMOVER SERVICIO DNS"

    $opc = Read-host "ingrese una opcion:"  

    switch($opc){

        1{
            $verificar = get-WindowsFeature DNS
            if ($verificar.Installed){
                write-host "el servicio DNS esta instalado!" -ForegroundColor Green
            }else{
                write-host "el servicio no esta instalado" -ForegroundColor Yellow
            }
        }

        2{
            install-WindowsFeature DNS
        }
            
        3{
            remove-WindowsFeature DNS
        }
    }

    write host "ingrese 'salir' para pasar a el siguiente procedimiento"
}while($opc -ne "salir")



