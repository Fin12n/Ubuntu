#!/bin/bash

##############################################
# Pterodactyl Quick Fix Script
# Auto-detect và fix các lỗi thường gặp
# Hỗ trợ: Ubuntu 20.04/22.04/24.04
##############################################

set -e

# Màu sắc
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

LOG_FILE="/var/log/pterodactyl_quickfix_$(date +%Y%m%d_%H%M%S).log"
PTERO_DIR="/var/www/pterodactyl"
ISSUES_FOUND=0
ISSUES_FIXED=0

# Hàm log
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_issue() {
    echo -e "${YELLOW}[ISSUE #$ISSUES_FOUND]${NC} $1" | tee -a "$LOG_FILE"
}

log_fix() {
    echo -e "${GREEN}[FIXED #$ISSUES_FIXED]${NC} $1" | tee -a "$LOG_FILE"
}

# Banner
show_banner() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════╗
║                                                       ║
║    ___        _      _      _____ _                   ║
║   / _ \ _   _(_) ___| | __ |  ___(_)_  __             ║
║  | | | | | | | |/ __| |/ / | |_  | \ \/ /             ║
║  | |_| | |_| | | (__|   <  |  _| | |>  <              ║
║   \__\_\\__,_|_|\___|_|\_\ |_|   |_/_/\_\             ║
║                                                       ║
║         Pterodactyl Auto Troubleshooter               ║
║                                                       ║
╚═══════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Kiểm tra root
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        log_error "Script phải chạy với quyền root!"
        exit 1
    fi
}

# Confirm
confirm() {
    read -p "$1 [y/N]: " response
    [[ "$response" =~ ^[Yy]$ ]]
}

# Auto confirm (dùng cho auto mode)
auto_confirm() {
    return 0
}

# Phát hiện lỗi 1: Permission issues
check_permissions() {
    log_info "━━━ Kiểm tra Permissions ━━━"
    
    if [ ! -d "$PTERO_DIR" ]; then
        log_warning "Pterodactyl directory không tồn tại!"
        return
    fi
    
    # Kiểm tra owner
    local current_owner=$(stat -c '%U:%G' "$PTERO_DIR" 2>/dev/null || echo "unknown")
    local expected_owner="www-data:www-data"
    
    if [ "$current_owner" != "$expected_owner" ]; then
        ((ISSUES_FOUND++))
        log_issue "Sai owner: $current_owner (mong đợi: $expected_owner)"
        
        if confirm "Bạn có muốn fix permissions không?"; then
            fix_permissions
        fi
    else
        log_success "✓ Permissions OK"
    fi
}

# Fix permissions
fix_permissions() {
    log "Đang fix permissions..."
    
    cd "$PTERO_DIR" || return 1
    
    # Set owner
    chown -R www-data:www-data "$PTERO_DIR" 2>&1 | tee -a "$LOG_FILE"
    
    # Set permissions cho directories
    find "$PTERO_DIR" -type d -exec chmod 755 {} \; 2>&1 | tee -a "$LOG_FILE"
    
    # Set permissions cho files
    find "$PTERO_DIR" -type f -exec chmod 644 {} \; 2>&1 | tee -a "$LOG_FILE"
    
    # Storage permissions
    chmod -R 755 storage/* bootstrap/cache 2>&1 | tee -a "$LOG_FILE"
    
    ((ISSUES_FIXED++))
    log_fix "Đã fix permissions"
}

# Phát hiện lỗi 2: Database connection issues
check_database() {
    log_info "━━━ Kiểm tra Database Connection ━━━"
    
    if [ ! -f "$PTERO_DIR/.env" ]; then
        log_warning ".env file không tồn tại!"
        return
    fi
    
    cd "$PTERO_DIR" || return
    
    # Test database connection
    if ! php artisan db:monitor 2>&1 | grep -q "OK"; then
        if ! mysql -e "SELECT 1;" 2>/dev/null; then
            ((ISSUES_FOUND++))
            log_issue "Không thể kết nối MySQL database"
            
            if confirm "Bạn có muốn restart MySQL service?"; then
                fix_database_connection
            fi
        fi
    else
        log_success "✓ Database connection OK"
    fi
}

# Fix database connection
fix_database_connection() {
    log "Đang restart MySQL service..."
    
    # Detect MySQL service name
    if systemctl list-units --type=service | grep -q "mariadb"; then
        systemctl restart mariadb 2>&1 | tee -a "$LOG_FILE"
        log_info "Đã restart MariaDB"
    elif systemctl list-units --type=service | grep -q "mysql"; then
        systemctl restart mysql 2>&1 | tee -a "$LOG_FILE"
        log_info "Đã restart MySQL"
    fi
    
    sleep 3
    
    # Test lại
    if mysql -e "SELECT 1;" 2>/dev/null; then
        ((ISSUES_FIXED++))
        log_fix "Database connection đã hoạt động"
    else
        log_error "Vẫn không thể kết nối database!"
    fi
}

# Phát hiện lỗi 3: Queue not running
check_queue() {
    log_info "━━━ Kiểm tra Queue Service ━━━"
    
    if ! systemctl is-active --quiet pteroq 2>/dev/null; then
        ((ISSUES_FOUND++))
        log_issue "Queue service (pteroq) không chạy"
        
        if confirm "Bạn có muốn restart queue service?"; then
            fix_queue_service
        fi
    else
        log_success "✓ Queue service đang chạy"
    fi
}

# Fix queue service
fix_queue_service() {
    log "Đang restart queue service..."
    
    systemctl restart pteroq 2>&1 | tee -a "$LOG_FILE"
    systemctl enable pteroq 2>&1 | tee -a "$LOG_FILE"
    
    sleep 2
    
    if systemctl is-active --quiet pteroq; then
        ((ISSUES_FIXED++))
        log_fix "Queue service đã hoạt động"
    else
        log_error "Không thể start queue service!"
    fi
}

# Phát hiện lỗi 4: Composer dependencies
check_composer_dependencies() {
    log_info "━━━ Kiểm tra Composer Dependencies ━━━"
    
    if [ ! -d "$PTERO_DIR/vendor" ]; then
        ((ISSUES_FOUND++))
        log_issue "Composer vendor directory không tồn tại"
        
        if confirm "Bạn có muốn cài đặt composer dependencies?"; then
            fix_composer_dependencies
        fi
    else
        log_success "✓ Composer dependencies OK"
    fi
}

# Fix composer dependencies
fix_composer_dependencies() {
    log "Đang cài đặt composer dependencies..."
    
    cd "$PTERO_DIR" || return 1
    
    composer install --no-dev --optimize-autoloader 2>&1 | tee -a "$LOG_FILE"
    
    if [ -d "$PTERO_DIR/vendor" ]; then
        ((ISSUES_FIXED++))
        log_fix "Đã cài đặt composer dependencies"
    else
        log_error "Không thể cài đặt dependencies!"
    fi
}

# Phát hiện lỗi 5: Cache issues
check_cache() {
    log_info "━━━ Kiểm tra Cache ━━━"
    
    cd "$PTERO_DIR" || return
    
    # Luôn clear cache để đảm bảo
    ((ISSUES_FOUND++))
    log_issue "Nên clear cache định kỳ"
    
    if confirm "Bạn có muốn clear tất cả cache?"; then
        fix_cache
    fi
}

# Fix cache
fix_cache() {
    log "Đang clear cache..."
    
    cd "$PTERO_DIR" || return 1
    
    php artisan cache:clear 2>&1 | tee -a "$LOG_FILE"
    php artisan config:clear 2>&1 | tee -a "$LOG_FILE"
    php artisan view:clear 2>&1 | tee -a "$LOG_FILE"
    php artisan route:clear 2>&1 | tee -a "$LOG_FILE"
    
    # Rebuild cache
    php artisan config:cache 2>&1 | tee -a "$LOG_FILE"
    php artisan route:cache 2>&1 | tee -a "$LOG_FILE"
    
    ((ISSUES_FIXED++))
    log_fix "Đã clear và rebuild cache"
}

# Phát hiện lỗi 6: Storage permissions
check_storage() {
    log_info "━━━ Kiểm tra Storage Permissions ━━━"
    
    if [ ! -d "$PTERO_DIR/storage" ]; then
        ((ISSUES_FOUND++))
        log_issue "Storage directory không tồn tại"
        return
    fi
    
    # Kiểm tra writable
    if [ ! -w "$PTERO_DIR/storage" ]; then
        ((ISSUES_FOUND++))
        log_issue "Storage directory không writable"
        
        if confirm "Bạn có muốn fix storage permissions?"; then
            fix_storage_permissions
        fi
    else
        log_success "✓ Storage permissions OK"
    fi
}

# Fix storage permissions
fix_storage_permissions() {
    log "Đang fix storage permissions..."
    
    cd "$PTERO_DIR" || return 1
    
    chmod -R 755 storage/* bootstrap/cache 2>&1 | tee -a "$LOG_FILE"
    chown -R www-data:www-data storage/* bootstrap/cache 2>&1 | tee -a "$LOG_FILE"
    
    ((ISSUES_FIXED++))
    log_fix "Đã fix storage permissions"
}

# Phát hiện lỗi 7: Web server issues
check_webserver() {
    log_info "━━━ Kiểm tra Web Server ━━━"
    
    local webserver=""
    
    if systemctl is-active --quiet nginx; then
        webserver="nginx"
    elif systemctl is-active --quiet apache2; then
        webserver="apache2"
    else
        ((ISSUES_FOUND++))
        log_issue "Không có web server nào đang chạy"
        
        if confirm "Bạn có muốn start nginx?"; then
            fix_webserver
        fi
        return
    fi
    
    log_success "✓ Web server ($webserver) đang chạy"
}

# Fix web server
fix_webserver() {
    log "Đang restart web server..."
    
    if systemctl list-units --type=service | grep -q "nginx"; then
        systemctl restart nginx 2>&1 | tee -a "$LOG_FILE"
        systemctl enable nginx 2>&1 | tee -a "$LOG_FILE"
        ((ISSUES_FIXED++))
        log_fix "Đã restart nginx"
    elif systemctl list-units --type=service | grep -q "apache2"; then
        systemctl restart apache2 2>&1 | tee -a "$LOG_FILE"
        systemctl enable apache2 2>&1 | tee -a "$LOG_FILE"
        ((ISSUES_FIXED++))
        log_fix "Đã restart apache2"
    fi
}

# Phát hiện lỗi 8: PHP-FPM issues
check_php_fpm() {
    log_info "━━━ Kiểm tra PHP-FPM ━━━"
    
    # Detect PHP version
    local php_version=$(php -v 2>/dev/null | head -n1 | cut -d' ' -f2 | cut -d'.' -f1,2)
    
    if [ -z "$php_version" ]; then
        log_warning "Không tìm thấy PHP!"
        return
    fi
    
    local service_name="php${php_version}-fpm"
    
    if ! systemctl is-active --quiet "$service_name" 2>/dev/null; then
        ((ISSUES_FOUND++))
        log_issue "PHP-FPM ($service_name) không chạy"
        
        if confirm "Bạn có muốn restart PHP-FPM?"; then
            fix_php_fpm "$service_name"
        fi
    else
        log_success "✓ PHP-FPM đang chạy"
    fi
}

# Fix PHP-FPM
fix_php_fpm() {
    local service_name=$1
    log "Đang restart PHP-FPM..."
    
    systemctl restart "$service_name" 2>&1 | tee -a "$LOG_FILE"
    systemctl enable "$service_name" 2>&1 | tee -a "$LOG_FILE"
    
    sleep 2
    
    if systemctl is-active --quiet "$service_name"; then
        ((ISSUES_FIXED++))
        log_fix "PHP-FPM đã hoạt động"
    else
        log_error "Không thể start PHP-FPM!"
    fi
}

# Phát hiện lỗi 9: Redis issues
check_redis() {
    log_info "━━━ Kiểm tra Redis ━━━"
    
    if command -v redis-cli &> /dev/null; then
        if ! redis-cli ping &> /dev/null; then
            ((ISSUES_FOUND++))
            log_issue "Redis không response"
            
            if confirm "Bạn có muốn restart Redis?"; then
                fix_redis
            fi
        else
            log_success "✓ Redis đang chạy"
        fi
    else
        log_info "Redis không được cài đặt (optional)"
    fi
}

# Fix Redis
fix_redis() {
    log "Đang restart Redis..."
    
    systemctl restart redis-server 2>&1 | tee -a "$LOG_FILE" || systemctl restart redis 2>&1 | tee -a "$LOG_FILE"
    
    sleep 2
    
    if redis-cli ping &> /dev/null; then
        ((ISSUES_FIXED++))
        log_fix "Redis đã hoạt động"
    else
        log_error "Không thể start Redis!"
    fi
}

# Phát hiện lỗi 10: .env file issues
check_env_file() {
    log_info "━━━ Kiểm tra .env File ━━━"
    
    if [ ! -f "$PTERO_DIR/.env" ]; then
        ((ISSUES_FOUND++))
        log_issue ".env file không tồn tại"
        
        if [ -f "$PTERO_DIR/.env.example" ]; then
            if confirm "Bạn có muốn tạo .env từ .env.example?"; then
                fix_env_file
            fi
        else
            log_error ".env.example cũng không tồn tại!"
        fi
    else
        # Kiểm tra APP_KEY
        if ! grep -q "APP_KEY=base64:" "$PTERO_DIR/.env"; then
            ((ISSUES_FOUND++))
            log_issue "APP_KEY chưa được generate"
            
            if confirm "Bạn có muốn generate APP_KEY?"; then
                fix_app_key
            fi
        else
            log_success "✓ .env file OK"
        fi
    fi
}

# Fix .env file
fix_env_file() {
    log "Đang tạo .env file..."
    
    cd "$PTERO_DIR" || return 1
    
    cp .env.example .env 2>&1 | tee -a "$LOG_FILE"
    
    # Generate APP_KEY
    php artisan key:generate --force 2>&1 | tee -a "$LOG_FILE"
    
    ((ISSUES_FIXED++))
    log_fix "Đã tạo .env file"
    log_warning "QUAN TRỌNG: Bạn cần cấu hình database trong .env!"
}

# Fix APP_KEY
fix_app_key() {
    log "Đang generate APP_KEY..."
    
    cd "$PTERO_DIR" || return 1
    
    php artisan key:generate --force 2>&1 | tee -a "$LOG_FILE"
    
    ((ISSUES_FIXED++))
    log_fix "Đã generate APP_KEY"
}

# Phát hiện lỗi 11: Node modules
check_node_modules() {
    log_info "━━━ Kiểm tra Node Modules ━━━"
    
    if [ ! -d "$PTERO_DIR/node_modules" ]; then
        ((ISSUES_FOUND++))
        log_issue "node_modules không tồn tại"
        
        if confirm "Bạn có muốn cài đặt node modules?"; then
            fix_node_modules
        fi
    else
        log_success "✓ Node modules OK"
    fi
}

# Fix node modules
fix_node_modules() {
    log "Đang cài đặt node modules..."
    
    cd "$PTERO_DIR" || return 1
    
    if command -v yarn &> /dev/null; then
        yarn install 2>&1 | tee -a "$LOG_FILE"
    else
        npm install 2>&1 | tee -a "$LOG_FILE"
    fi
    
    if [ -d "$PTERO_DIR/node_modules" ]; then
        ((ISSUES_FIXED++))
        log_fix "Đã cài đặt node modules"
    else
        log_error "Không thể cài đặt node modules!"
    fi
}

# Phát hiện lỗi 12: Disk space
check_disk_space() {
    log_info "━━━ Kiểm tra Disk Space ━━━"
    
    local usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [ "$usage" -gt 90 ]; then
        ((ISSUES_FOUND++))
        log_issue "Disk space sử dụng ${usage}% (> 90%)"
        log_warning "Bạn nên dọn dẹp disk space!"
        
        if confirm "Bạn có muốn xem top 10 thư mục lớn nhất?"; then
            du -ah / 2>/dev/null | sort -rh | head -n 10
        fi
    elif [ "$usage" -gt 80 ]; then
        log_warning "Disk space sử dụng ${usage}% (cảnh báo: > 80%)"
    else
        log_success "✓ Disk space OK (${usage}%)"
    fi
}

# Auto Fix All
auto_fix_all() {
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "AUTO FIX MODE - Tự động fix tất cả lỗi"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Override confirm function
    confirm() { return 0; }
    
    run_all_checks
    
    echo ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_success "AUTO FIX HOÀN TẤT"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Run all checks
run_all_checks() {
    ISSUES_FOUND=0
    ISSUES_FIXED=0
    
    check_permissions
    echo ""
    check_database
    echo ""
    check_queue
    echo ""
    check_composer_dependencies
    echo ""
    check_cache
    echo ""
    check_storage
    echo ""
    check_webserver
    echo ""
    check_php_fpm
    echo ""
    check_redis
    echo ""
    check_env_file
    echo ""
    check_node_modules
    echo ""
    check_disk_space
}

# Show summary
show_summary() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}             SUMMARY REPORT              ${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${YELLOW}Issues Found:${NC}  $ISSUES_FOUND"
    echo -e "  ${GREEN}Issues Fixed:${NC}  $ISSUES_FIXED"
    echo ""
    echo -e "  ${BLUE}Log File:${NC}     $LOG_FILE"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Menu chính
show_menu() {
    show_banner
    echo -e "${YELLOW}Log file: $LOG_FILE${NC}"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "1) 🔍 Scan toàn bộ (Manual Fix)"
    echo "2) 🤖 Auto Fix tất cả"
    echo "3) 🔧 Fix từng vấn đề cụ thể:"
    echo "   ├─ 31) Permissions"
    echo "   ├─ 32) Database Connection"
    echo "   ├─ 33) Queue Service"
    echo "   ├─ 34) Composer Dependencies"
    echo "   ├─ 35) Cache"
    echo "   ├─ 36) Storage Permissions"
    echo "   ├─ 37) Web Server"
    echo "   ├─ 38) PHP-FPM"
    echo "   ├─ 39) Redis"
    echo "   ├─ 40) .env File"
    echo "   └─ 41) Node Modules"
    echo "0) Thoát"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Main
main() {
    check_root
    
    while true; do
        show_menu
        read -p "Chọn tùy chọn: " choice
        
        case $choice in
            1)
                clear
                show_banner
                run_all_checks
                show_summary
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            2)
                clear
                show_banner
                auto_fix_all
                show_summary
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            31)
                clear
                show_banner
                check_permissions
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            32)
                clear
                show_banner
                check_database
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            33)
                clear
                show_banner
                check_queue
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            34)
                clear
                show_banner
                check_composer_dependencies
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            35)
                clear
                show_banner
                check_cache
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            36)
                clear
                show_banner
                check_storage
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            37)
                clear
                show_banner
                check_webserver
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            38)
                clear
                show_banner
                check_php_fpm
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            39)
                clear
                show_banner
                check_redis
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            40)
                clear
                show_banner
                check_env_file
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            41)
                clear
                show_banner
                check_node_modules
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            0)
                log "Thoát script"
                echo ""
                echo -e "${GREEN}Cảm ơn bạn đã sử dụng Quick Fix!${NC}"
                echo ""
                exit 0
                ;;
            *)
                log_error "Lựa chọn không hợp lệ"
                sleep 2
                ;;
        esac
    done
}

# Run
main
