#!/bin/sh
# =============================================================================
# main.sh — Script principal de aprovisionamiento web
# Proyecto : Aprovisionamiento Web Automatizado
# SO       : Alpine Linux 3.23
# Uso      : sudo sh main.sh [-i|-v|-r]
# =============================================================================

# Cargar librerías
. ./lib/utils.sh
. ./lib/http_functions.sh

# -----------------------------------------------------------------------------
# MENÚ PRINCIPAL
# -----------------------------------------------------------------------------
menu_principal() {
    while true; do
        clear
        print_title "Aprovisionamiento Web Automatizado"
        print_menu " [1] Instalar servidor HTTP"
        print_menu " [2] Ver estado de servidores"
        print_menu " [3] Revisar respuesta HTTP (curl)"
        print_menu " [0] Salir"
        printf "\n${C_PINK}Selecciona una opcion: ${C_RESET}"
        read opcion
        
        case "$opcion" in
            1) menu_instalacion ;;
            2) verificar_HTTP; pausar ;;
            3) revisar_HTTP; pausar ;;
            0) print_success "Saliendo..."; exit 0 ;;
            *) print_warning "Opción inválida." ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# SUBMENÚ INSTALACIÓN
# -----------------------------------------------------------------------------
menu_instalacion() {
    clear
    print_title "Instalar Servidor HTTP"
    print_menu "  [1] Apache2"
    print_menu "  [2] Nginx"
    print_menu "  [3] Tomcat"
    print_menu "  [0] Volver"
    printf "\n${C_PINK}Selecciona un servidor: ${C_RESET}"
    read opcion
    
    case "$opcion" in
        1) setup_apache; pausar ;;
        2) setup_nginx; pausar ;;
        3) setup_tomcat; pausar ;;
        0) return ;;
        *) print_warning "Opción inválida."; pausar ;;
    esac
}

# -----------------------------------------------------------------------------
# INICIO — soporta flags o menú interactivo
# -----------------------------------------------------------------------------
verificar_root

case "$1" in
    -i|--instalar)  menu_instalacion ;;
    -v|--verificar) verificar_HTTP; pausar ;;
    -r|--revisar)   revisar_HTTP; pausar ;;
    -h|--help)
        printf "\n${C_PINK}USO:${C_RESET}\n"
        print_menu "  ./main.sh          Menú interactivo"
        print_menu "  ./main.sh -i       Instalar servidor HTTP"
        print_menu "  ./main.sh -v       Ver estado de servidores"
        print_menu "  ./main.sh -r       Revisar respuesta HTTP (curl)"
        print_menu "  ./main.sh -h       Mostrar esta ayuda"
        printf "\n"
        ;;
    "")  menu_principal ;;
    *)
        print_warning "Opción inválida. Usa: ./main.sh -h para ver ayuda"
        ;;
esac
