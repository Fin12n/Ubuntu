#!/bin/bash
# Menu | Pterodactyl Panel By Fin12n

while true; do
    clear
    echo "=================================="
    echo "   Menu | Pterodactyl Panel By Fin12n"
    echo "=================================="
    echo "0) Cài đặt Panel"
    echo "1) Cài đặt Blueprint"
    echo "2) Xóa sạch sẽ Panel"
    echo "3) Fix lỗi nhanh"
    echo "4) Detect lỗi nhanh"
    echo "5) Test panel/wings"
    echo "6) Thoát"
    echo "=================================="
    read -p "Chọn số (1-6): " choice

    case $choice in
        0) 
            echo "▶ Cài đặt Panel..."
            bash <(curl -s https://pterodactyl-installer.se) 
            ;;
        1) 
            echo "▶ Cài đặt Blueprint"
            bash <(curl -s https://raw.githubusercontent.com/Fin12n/Ubuntu/refs/heads/main/Pterodactyl-Panel/install-blueprint.sh)
        2) 
            echo "▶ Xóa sạch sẽ Panel..."
            bash <(curl -s https://raw.githubusercontent.com/Fin12n/Ubuntu/refs/heads/main/Pterodactyl-Panel/cleaner.sh) 
            ;;
        3) 
            echo "▶ Fix lỗi nhanh..."
            bash <(curl -s https://raw.githubusercontent.com/Fin12n/Ubuntu/refs/heads/main/Pterodactyl-Panel/quickfix.sh) 
            ;;
        4) 
            echo "▶ Detect lỗi nhanh..."
            bash <(curl -s https://raw.githubusercontent.com/Fin12n/Ubuntu/refs/heads/main/Pterodactyl-Panel/quickerrorcheck.sh) 
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
