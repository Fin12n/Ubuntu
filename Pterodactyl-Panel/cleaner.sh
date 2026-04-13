#!/bin/bash

##############################################
# Pterodactyl Panel Complete Uninstaller
# Hỗ trợ: Ubuntu 20.04/22.04/24.04
# Tác giả: Auto-generated
##############################################

set -e

# Màu sắc cho output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

LOG_FILE="/var/log/pterodactyl_uninstall_$(date +%Y%m%d_%H%M%S).log"

# Hàm log
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR $(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING $(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

# Kiểm tra quyền root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        log_error "Script phải chạy với quyền root!"
        exit 1
    fi
}

# Xác nhận từ user
confirm() {
    local prompt="$1"
    local default="${2:-n}"
    
    if [ "$default" = "y" ]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi
    
    read -p "$prompt" response
    response=${response,,}
    
    if [ "$default" = "y" ]; then
        [[ "$response" =~ ^(yes|y|)$ ]]
    else
        [[ "$response" =~ ^(yes|y)$ ]]
    fi
}

# Kiểm tra và dừng service
stop_service() {
    local service_name=$1
    if systemctl is-active --quiet "$service_name" 2>/dev/null; then
        log "Đang dừng service: $service_name"
        systemctl stop "$service_name" 2>&1 | tee -a "$LOG_FILE" || log_warning "Không thể dừng $service_name"
        systemctl disable "$service_name" 2>&1 | tee -a "$LOG_FILE" || log_warning "Không thể disable $service_name"
    fi
}

# Xóa Panel Web
remove_panel() {
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Bắt đầu gỡ Pterodactyl Panel (Web Interface)"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Dừng các service liên quan
    stop_service "pteroq"
    stop_service "pteroq.service"
    
    # Xóa thư mục panel
    local panel_dirs=(
        "/var/www/pterodactyl"
        "/var/www/html/pterodactyl"
    )
    
    for dir in "${panel_dirs[@]}"; do
        if [ -d "$dir" ]; then
            log "Xóa thư mục: $dir"
            rm -rf "$dir" 2>&1 | tee -a "$LOG_FILE"
        fi
    done
    
    # Xóa systemd service files
    local service_files=(
        "/etc/systemd/system/pteroq.service"
    )
    
    for file in "${service_files[@]}"; do
        if [ -f "$file" ]; then
            log "Xóa service file: $file"
            rm -f "$file" 2>&1 | tee -a "$LOG_FILE"
        fi
    done
    
    systemctl daemon-reload 2>&1 | tee -a "$LOG_FILE"
    
    # Xóa Nginx/Apache config
    log "Xóa cấu hình web server..."
    rm -f /etc/nginx/sites-enabled/pterodactyl.conf 2>/dev/null || true
    rm -f /etc/nginx/sites-available/pterodactyl.conf 2>/dev/null || true
    rm -f /etc/apache2/sites-enabled/pterodactyl.conf 2>/dev/null || true
    rm -f /etc/apache2/sites-available/pterodactyl.conf 2>/dev/null || true
    
    # Reload web server
    if systemctl is-active --quiet nginx; then
        systemctl reload nginx 2>&1 | tee -a "$LOG_FILE" || log_warning "Không thể reload nginx"
    fi
    
    if systemctl is-active --quiet apache2; then
        systemctl reload apache2 2>&1 | tee -a "$LOG_FILE" || log_warning "Không thể reload apache2"
    fi
    
    # Detect và kiểm tra
    detect_panel_remnants
    
    log "${GREEN}✓ Hoàn thành gỡ Panel${NC}"
}

# Detect các file còn sót của Panel
detect_panel_remnants() {
    log_info "Đang kiểm tra các file còn sót của Panel..."
    
    local remnants=()
    
    # Kiểm tra thư mục
    [ -d "/var/www/pterodactyl" ] && remnants+=("/var/www/pterodactyl")
    [ -d "/var/www/html/pterodactyl" ] && remnants+=("/var/www/html/pterodactyl")
    
    # Kiểm tra service
    [ -f "/etc/systemd/system/pteroq.service" ] && remnants+=("/etc/systemd/system/pteroq.service")
    
    if [ ${#remnants[@]} -gt 0 ]; then
        log_warning "Phát hiện ${#remnants[@]} file/thư mục còn sót:"
        for item in "${remnants[@]}"; do
            log_warning "  - $item"
        done
        
        if confirm "Bạn có muốn xóa các file này không?"; then
            for item in "${remnants[@]}"; do
                log "Xóa: $item"
                rm -rf "$item" 2>&1 | tee -a "$LOG_FILE"
            done
        fi
    else
        log_info "✓ Không phát hiện file còn sót"
    fi
}

# Xóa Wings
remove_wings() {
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Bắt đầu gỡ Pterodactyl Wings"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Dừng Wings
    stop_service "wings"
    stop_service "wings.service"
    
    # Xóa Wings binary
    if [ -f "/usr/local/bin/wings" ]; then
        log "Xóa Wings binary"
        rm -f /usr/local/bin/wings 2>&1 | tee -a "$LOG_FILE"
    fi
    
    # Xóa thư mục config và data
    local wings_dirs=(
        "/etc/pterodactyl"
        "/var/lib/pterodactyl"
        "/var/log/pterodactyl"
    )
    
    for dir in "${wings_dirs[@]}"; do
        if [ -d "$dir" ]; then
            log "Xóa thư mục: $dir"
            rm -rf "$dir" 2>&1 | tee -a "$LOG_FILE"
        fi
    done
    
    # Xóa service file
    if [ -f "/etc/systemd/system/wings.service" ]; then
        log "Xóa Wings service file"
        rm -f /etc/systemd/system/wings.service 2>&1 | tee -a "$LOG_FILE"
    fi
    
    systemctl daemon-reload 2>&1 | tee -a "$LOG_FILE"
    
    # Xóa Docker containers và networks của Pterodactyl
    if command -v docker &> /dev/null; then
        log "Dọn dẹp Docker containers của Pterodactyl..."
        docker ps -a | grep pterodactyl | awk '{print $1}' | xargs -r docker rm -f 2>&1 | tee -a "$LOG_FILE" || true
        docker network ls | grep pterodactyl | awk '{print $1}' | xargs -r docker network rm 2>&1 | tee -a "$LOG_FILE" || true
    fi
    
    # Detect và kiểm tra
    detect_wings_remnants
    
    log "${GREEN}✓ Hoàn thành gỡ Wings${NC}"
}

# Detect các file còn sót của Wings
detect_wings_remnants() {
    log_info "Đang kiểm tra các file còn sót của Wings..."
    
    local remnants=()
    
    [ -f "/usr/local/bin/wings" ] && remnants+=("/usr/local/bin/wings")
    [ -d "/etc/pterodactyl" ] && remnants+=("/etc/pterodactyl")
    [ -d "/var/lib/pterodactyl" ] && remnants+=("/var/lib/pterodactyl")
    [ -f "/etc/systemd/system/wings.service" ] && remnants+=("/etc/systemd/system/wings.service")
    
    if [ ${#remnants[@]} -gt 0 ]; then
        log_warning "Phát hiện ${#remnants[@]} file/thư mục còn sót:"
        for item in "${remnants[@]}"; do
            log_warning "  - $item"
        done
        
        if confirm "Bạn có muốn xóa các file này không?"; then
            for item in "${remnants[@]}"; do
                log "Xóa: $item"
                rm -rf "$item" 2>&1 | tee -a "$LOG_FILE"
            done
        fi
    else
        log_info "✓ Không phát hiện file còn sót"
    fi
}

# Xóa Packages
remove_packages() {
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Bắt đầu gỡ các Package"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Packages có thể gỡ an toàn (không ảnh hưởng hệ thống)
    local removable_packages=(
        "php8.1-*"
        "php8.2-*"
        "php8.3-*"
        "composer"
        "redis-server"
        "certbot"
        "python3-certbot-nginx"
    )
    
    # Packages nên giữ lại (quan trọng cho hệ thống)
    local keep_packages=(
        "nginx"
        "mysql-server"
        "mariadb-server"
        "docker-ce"
        "docker-compose"
        "git"
        "curl"
        "wget"
        "tar"
        "unzip"
        "software-properties-common"
    )
    
    log_info "Các package sẽ KHÔNG bị xóa (quan trọng cho hệ thống):"
    for pkg in "${keep_packages[@]}"; do
        log_info "  - $pkg"
    done
    
    echo ""
    log_info "Các package CÓ THỂ xóa (liên quan đến Pterodactyl):"
    for pkg in "${removable_packages[@]}"; do
        log_info "  - $pkg"
    done
    
    echo ""
    if confirm "Bạn có muốn gỡ các PHP packages và Redis?"; then
        for pkg in "${removable_packages[@]}"; do
            if dpkg -l | grep -q "^ii.*$pkg"; then
                log "Gỡ package: $pkg"
                apt-get remove --purge -y $pkg 2>&1 | tee -a "$LOG_FILE" || log_warning "Không thể gỡ $pkg"
            fi
        done
        
        apt-get autoremove -y 2>&1 | tee -a "$LOG_FILE"
        apt-get autoclean -y 2>&1 | tee -a "$LOG_FILE"
    fi
    
    # Xóa repository
    if [ -f "/etc/apt/sources.list.d/ondrej-ubuntu-php-*.list" ]; then
        log "Xóa PHP repository"
        rm -f /etc/apt/sources.list.d/ondrej-ubuntu-php-*.list
    fi
    
    log "${GREEN}✓ Hoàn thành gỡ packages${NC}"
}

# Xóa Database
remove_database() {
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Bắt đầu gỡ Database"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    log_warning "CẢNH BÁO: Bước này sẽ XÓA DATABASE của Pterodactyl!"
    log_warning "Tất cả dữ liệu về servers, users, nodes sẽ BỊ MẤT VĨNH VIỄN!"
    
    if ! confirm "Bạn CHẮC CHẮN muốn xóa database?"; then
        log "Bỏ qua xóa database"
        return
    fi
    
    # Xác nhận lần 2
    if ! confirm "Xác nhận lần 2: XÓA TẤT CẢ DATABASE?"; then
        log "Bỏ qua xóa database"
        return
    fi
    
    # Kiểm tra MySQL/MariaDB
    if command -v mysql &> /dev/null; then
        log "Đang xóa database Pterodactyl..."
        
        # Xóa database panel
        mysql -e "DROP DATABASE IF EXISTS panel;" 2>&1 | tee -a "$LOG_FILE" || log_warning "Không thể xóa database 'panel'"
        mysql -e "DROP DATABASE IF EXISTS pterodactyl;" 2>&1 | tee -a "$LOG_FILE" || log_warning "Không thể xóa database 'pterodactyl'"
        
        # Xóa users
        mysql -e "DROP USER IF EXISTS 'pterodactyl'@'127.0.0.1';" 2>&1 | tee -a "$LOG_FILE" || true
        mysql -e "DROP USER IF EXISTS 'pterodactyluser'@'127.0.0.1';" 2>&1 | tee -a "$LOG_FILE" || true
        mysql -e "DROP USER IF EXISTS 'pterodactyl'@'localhost';" 2>&1 | tee -a "$LOG_FILE" || true
        mysql -e "DROP USER IF EXISTS 'pterodactyluser'@'localhost';" 2>&1 | tee -a "$LOG_FILE" || true
        
        mysql -e "FLUSH PRIVILEGES;" 2>&1 | tee -a "$LOG_FILE"
        
        log "${GREEN}✓ Đã xóa database${NC}"
    else
        log_warning "MySQL/MariaDB không được cài đặt hoặc không chạy"
    fi
}

# Xóa tất cả
remove_all() {
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "GỠ CÀI ĐẶT HOÀN TOÀN PTERODACTYL"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    log_warning "CẢNH BÁO: Bước này sẽ xóa TẤT CẢ:"
    log_warning "  - Panel Web"
    log_warning "  - Wings"
    log_warning "  - Database (TẤT CẢ DỮ LIỆU)"
    log_warning "  - PHP Packages"
    
    if ! confirm "Bạn CHẮC CHẮN muốn xóa tất cả?"; then
        log "Đã hủy"
        exit 0
    fi
    
    remove_panel
    remove_wings
    remove_database
    remove_packages
    
    log ""
    log "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "${GREEN}✓ ĐÃ GỠ HOÀN TOÀN PTERODACTYL${NC}"
    log "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Menu chính
show_menu() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   PTERODACTYL COMPLETE UNINSTALLER        ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Log file: $LOG_FILE${NC}"
    echo ""
    echo "1) Gỡ Panel Web (Pterodactyl)"
    echo "2) Gỡ Wings"
    echo "3) Gỡ Packages (PHP, Redis, etc.)"
    echo "4) Gỡ Database"
    echo "5) Gỡ TẤT CẢ (Panel + Wings + DB + Packages)"
    echo "0) Thoát"
    echo ""
}

# Main
main() {
    check_root
    
    log "Bắt đầu Pterodactyl Uninstaller"
    log "Log file: $LOG_FILE"
    
    while true; do
        show_menu
        read -p "Chọn tùy chọn [0-5]: " choice
        
        case $choice in
            1)
                remove_panel
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            2)
                remove_wings
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            3)
                remove_packages
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            4)
                remove_database
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            5)
                remove_all
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            0)
                log "Thoát script"
                exit 0
                ;;
            *)
                log_error "Lựa chọn không hợp lệ"
                sleep 2
                ;;
        esac
    done
}

# Chạy script
main
