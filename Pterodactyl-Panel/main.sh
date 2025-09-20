#!/bin/bash
# Menu | Pterodactyl Panel By Fin12n

while true; do
    clear
    echo "=================================="
    echo "   Menu | Pterodactyl Panel By Fin12n"
    echo "=================================="
    echo "1) Cài đặt Panel"
    echo "2) Xóa sạch sẽ Panel"
    echo "3) Fix lỗi nhanh"
    echo "4) Detect lỗi nhanh"
    echo "5) Test panel/wings"
    echo "6) Thoát"
    echo "=================================="
    read -p "Chọn số (1-6): " choice

    case $choice in
        1) 
            echo "▶ Đang cài đặt Panel..."
            bash <(curl -s https://pterodactyl-installer.se) 
            ;;
        2) 
            echo "▶ Xóa sạch sẽ Panel..."
            bash <(curl -s URL_XOA_PANEL) 
            ;;
        3) 
            echo "▶ Fix lỗi nhanh..."
            bash <(curl -s URL_FIX_LOI) 
            ;;
        4) 
            echo "▶ Detect lỗi nhanh..."
            bash <(curl -s URL_DETECT) 
            ;;
        5) 
            echo "▶ Test panel/wings..."
            bash <(curl -s URL_TEST) 
            ;;
        6) 
            echo "Thoát menu."
            exit 0 
            ;;
        *) 
            echo "⚠️ Lựa chọn không hợp lệ, vui lòng nhập từ 1-6."
            ;;
    esac

    echo ""
    read -p "Nhấn Enter để quay lại menu..."
done
