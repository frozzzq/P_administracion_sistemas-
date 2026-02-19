Write Host "======================================================================" -ForegroundColor Yellow
Write Host "                           SERVIDOR DNS                               "
Write Host "======================================================================" -ForegroundColor Yellow


do{
    write-host "[1] - VERIFICAR INSTALACION DNS"
    write-host "[2] - INSTALAR SERVICIO DNS"
    write-host "[3] - REMOVER SERVICIO DNS"
    write-host "[4] - CONFIGURAR IP"
    write-host "[5] - MONITOREO"

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
            $verificar = get-WindowsFeature DNS
            if ($verificar.Installed){
                write-host "servicio instalado, el servicio no necesita ser instalado" -ForegroundColor Yellow 
            }else{
                write-host "instalando servicio..."
                install-WindowsFeature DNS
            }
        }
            
        3{
            $verificar = get-WindowsFeature DNS
            if ($verificar.Installed){
                remove-WindowsFeature DNS
                write-host "servicio removido correctamente!" -ForegroundColor Green
            }else{
                write-host "el servicio no esta instalado!, ingrese otra opcion" -ForegroundColor Yellow
            }
        }

        4{





        }
    }

    write host "ingrese 'salir' para pasar a el siguiente procedimiento"
}while($opc -ne "salir")



