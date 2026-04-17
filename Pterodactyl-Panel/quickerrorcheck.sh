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

# Quick Diagnostic - Chỉ scan và báo cáo
quick_diagnostic() {
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "QUICK DIAGNOSTIC - Kiểm tra lỗi Panel"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Disable auto-fix
    local DIAGNOSTIC_MODE=true
    
    # Arrays để lưu kết quả
    local -a critical_issues=()
    local -a warnings=()
    local -a info_items=()
    local -a all_ok=()
    
    # 1. Kiểm tra Pterodactyl Directory
    log_info "━━━ 1/15: Pterodactyl Directory ━━━"
    if [ -d "$PTERO_DIR" ]; then
        all_ok+=("✓ Pterodactyl directory tồn tại")
        log_success "✓ Directory tồn tại: $PTERO_DIR"
    else
        critical_issues+=("✗ CRITICAL: Pterodactyl directory không tồn tại tại $PTERO_DIR")
        log_error "✗ Directory không tồn tại!"
    fi
    echo ""
    
    # 2. Kiểm tra Permissions
    log_info "━━━ 2/15: File Permissions ━━━"
    if [ -d "$PTERO_DIR" ]; then
        local current_owner=$(stat -c '%U:%G' "$PTERO_DIR" 2>/dev/null || echo "unknown")
        local expected_owner="www-data:www-data"
        
        if [ "$current_owner" = "$expected_owner" ]; then
            all_ok+=("✓ Permissions: $current_owner")
            log_success "✓ Owner đúng: $current_owner"
        else
            warnings+=("⚠ Owner không đúng: $current_owner (mong đợi: $expected_owner)")
            log_warning "⚠ Owner: $current_owner (nên là: $expected_owner)"
        fi
        
        # Kiểm tra storage writable
        if [ -w "$PTERO_DIR/storage" ]; then
            all_ok+=("✓ Storage writable")
            log_success "✓ Storage writable"
        else
            critical_issues+=("✗ Storage không writable")
            log_error "✗ Storage không writable"
        fi
    fi
    echo ""
    
    # 3. Kiểm tra .env File
    log_info "━━━ 3/15: Configuration Files ━━━"
    if [ -f "$PTERO_DIR/.env" ]; then
        all_ok+=("✓ .env file tồn tại")
        log_success "✓ .env tồn tại"
        
        # Kiểm tra APP_KEY
        if grep -q "APP_KEY=base64:" "$PTERO_DIR/.env"; then
            all_ok+=("✓ APP_KEY đã được generate")
            log_success "✓ APP_KEY OK"
        else
            critical_issues+=("✗ APP_KEY chưa được generate")
            log_error "✗ APP_KEY thiếu"
        fi
        
        # Kiểm tra DB config
        if grep -q "DB_HOST=" "$PTERO_DIR/.env"; then
            info_items+=("ℹ DB_HOST đã cấu hình")
            log_info "ℹ DB_HOST có cấu hình"
        fi
    else
        critical_issues+=("✗ CRITICAL: .env file không tồn tại")
        log_error "✗ .env không tồn tại"
    fi
    echo ""
    
    # 4. Kiểm tra Database Connection
    log_info "━━━ 4/15: Database Connection ━━━"
    if command -v mysql &> /dev/null; then
        if mysql -e "SELECT 1;" &> /dev/null; then
            all_ok+=("✓ MySQL connection OK")
            log_success "✓ MySQL kết nối thành công"
            
            # Kiểm tra databases
            local db_list=$(mysql -e "SHOW DATABASES;" 2>/dev/null | grep -iE "panel|pterodactyl")
            if [ -n "$db_list" ]; then
                info_items+=("ℹ Databases: $db_list")
                log_info "ℹ Tìm thấy databases: $db_list"
            fi
        else
            critical_issues+=("✗ Không thể kết nối MySQL")
            log_error "✗ MySQL connection failed"
        fi
    else
        warnings+=("⚠ MySQL client chưa cài đặt")
        log_warning "⚠ MySQL không có"
    fi
    echo ""
    
    # 5. Kiểm tra Web Server
    log_info "━━━ 5/15: Web Server ━━━"
    if systemctl is-active --quiet nginx 2>/dev/null; then
        all_ok+=("✓ Nginx đang chạy")
        log_success "✓ Nginx active"
        
        # Kiểm tra config
        if nginx -t &> /dev/null; then
            all_ok+=("✓ Nginx config hợp lệ")
            log_success "✓ Nginx config OK"
        else
            warnings+=("⚠ Nginx config có lỗi")
            log_warning "⚠ Nginx config error"
        fi
    elif systemctl is-active --quiet apache2 2>/dev/null; then
        all_ok+=("✓ Apache2 đang chạy")
        log_success "✓ Apache2 active"
    else
        critical_issues+=("✗ Không có web server nào chạy")
        log_error "✗ No web server running"
    fi
    echo ""
    
    # 6. Kiểm tra PHP-FPM
    log_info "━━━ 6/15: PHP & PHP-FPM ━━━"
    if command -v php &> /dev/null; then
        local php_version=$(php -v 2>/dev/null | head -n1 | cut -d' ' -f2)
        all_ok+=("✓ PHP $php_version installed")
        log_success "✓ PHP version: $php_version"
        
        # Kiểm tra PHP-FPM
        local php_ver=$(php -v 2>/dev/null | head -n1 | cut -d' ' -f2 | cut -d'.' -f1,2)
        local service_name="php${php_ver}-fpm"
        
        if systemctl is-active --quiet "$service_name" 2>/dev/null; then
            all_ok+=("✓ PHP-FPM đang chạy")
            log_success "✓ PHP-FPM active"
        else
            critical_issues+=("✗ PHP-FPM không chạy")
            log_error "✗ PHP-FPM inactive"
        fi
        
        # Kiểm tra PHP extensions
        local required_exts=("curl" "mbstring" "xml" "zip" "mysql")
        local missing_exts=()
        
        for ext in "${required_exts[@]}"; do
            if ! php -m | grep -qi "$ext"; then
                missing_exts+=("$ext")
            fi
        done
        
        if [ ${#missing_exts[@]} -eq 0 ]; then
            all_ok+=("✓ Tất cả PHP extensions cần thiết đã cài")
            log_success "✓ PHP extensions OK"
        else
            warnings+=("⚠ Thiếu PHP extensions: ${missing_exts[*]}")
            log_warning "⚠ Missing: ${missing_exts[*]}"
        fi
    else
        critical_issues+=("✗ CRITICAL: PHP chưa cài đặt")
        log_error "✗ PHP not found"
    fi
    echo ""
    
    # 7. Kiểm tra Queue Service
    log_info "━━━ 7/15: Queue Service ━━━"
    if systemctl is-active --quiet pteroq 2>/dev/null; then
        all_ok+=("✓ Queue service (pteroq) đang chạy")
        log_success "✓ pteroq active"
    else
        warnings+=("⚠ Queue service không chạy")
        log_warning "⚠ pteroq inactive"
    fi
    echo ""
    
    # 8. Kiểm tra Composer
    log_info "━━━ 8/15: Composer & Dependencies ━━━"
    if command -v composer &> /dev/null; then
        local composer_ver=$(composer --version 2>/dev/null | head -n1)
        all_ok+=("✓ Composer: $composer_ver")
        log_success "✓ $composer_ver"
        
        # Kiểm tra vendor
        if [ -d "$PTERO_DIR/vendor" ]; then
            all_ok+=("✓ Composer dependencies đã cài")
            log_success "✓ vendor/ exists"
        else
            critical_issues+=("✗ Composer vendor/ không tồn tại")
            log_error "✗ vendor/ missing"
        fi
    else
        critical_issues+=("✗ Composer chưa cài đặt")
        log_error "✗ Composer not found"
    fi
    echo ""
    
    # 9. Kiểm tra Node.js & NPM
    log_info "━━━ 9/15: Node.js & Package Manager ━━━"
    if command -v node &> /dev/null; then
        local node_ver=$(node -v 2>/dev/null)
        local node_major=$(echo $node_ver | cut -d'v' -f2 | cut -d'.' -f1)
        
        if [ "$node_major" -ge 18 ]; then
            all_ok+=("✓ Node.js $node_ver (>= 18)")
            log_success "✓ Node.js $node_ver"
        else
            warnings+=("⚠ Node.js $node_ver (nên >= 18)")
            log_warning "⚠ Node.js old version"
        fi
        
        # Kiểm tra Yarn
        if command -v yarn &> /dev/null; then
            local yarn_ver=$(yarn -v 2>/dev/null)
            all_ok+=("✓ Yarn $yarn_ver")
            log_success "✓ Yarn $yarn_ver"
        else
            warnings+=("⚠ Yarn chưa cài")
            log_warning "⚠ Yarn not found"
        fi
        
        # Kiểm tra node_modules
        if [ -d "$PTERO_DIR/node_modules" ]; then
            all_ok+=("✓ Node modules đã cài")
            log_success "✓ node_modules/ exists"
        else
            warnings+=("⚠ node_modules/ không tồn tại")
            log_warning "⚠ node_modules/ missing"
        fi
    else
        critical_issues+=("✗ Node.js chưa cài đặt")
        log_error "✗ Node.js not found"
    fi
    echo ""
    
    # 10. Kiểm tra Redis
    log_info "━━━ 10/15: Redis (Optional) ━━━"
    if command -v redis-cli &> /dev/null; then
        if redis-cli ping &> /dev/null; then
            all_ok+=("✓ Redis đang chạy")
            log_success "✓ Redis active"
        else
            warnings+=("⚠ Redis không response")
            log_warning "⚠ Redis not responding"
        fi
    else
        info_items+=("ℹ Redis không cài (optional)")
        log_info "ℹ Redis not installed"
    fi
    echo ""
    
    # 11. Kiểm tra Disk Space
    log_info "━━━ 11/15: Disk Space ━━━"
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    local disk_avail=$(df -h / | awk 'NR==2 {print $4}')
    
    if [ "$disk_usage" -gt 90 ]; then
        critical_issues+=("✗ Disk space: ${disk_usage}% (CRITICAL)")
        log_error "✗ Disk ${disk_usage}% (critical)"
    elif [ "$disk_usage" -gt 80 ]; then
        warnings+=("⚠ Disk space: ${disk_usage}% (cảnh báo)")
        log_warning "⚠ Disk ${disk_usage}%"
    else
        all_ok+=("✓ Disk space: ${disk_usage}% (Available: $disk_avail)")
        log_success "✓ Disk ${disk_usage}%"
    fi
    echo ""
    
    # 12. Kiểm tra Memory
    log_info "━━━ 12/15: Memory Usage ━━━"
    local mem_total=$(free -h | awk 'NR==2 {print $2}')
    local mem_used=$(free -h | awk 'NR==2 {print $3}')
    local mem_percent=$(free | awk 'NR==2 {printf "%.0f", $3/$2 * 100}')
    
    if [ "$mem_percent" -gt 90 ]; then
        warnings+=("⚠ Memory: ${mem_percent}% (${mem_used}/${mem_total})")
        log_warning "⚠ Memory ${mem_percent}%"
    else
        all_ok+=("✓ Memory: ${mem_percent}% (${mem_used}/${mem_total})")
        log_success "✓ Memory ${mem_percent}%"
    fi
    echo ""
    
    # 13. Kiểm tra SSL/HTTPS
    log_info "━━━ 13/15: SSL/HTTPS ━━━"
    if [ -d "/etc/letsencrypt/live" ]; then
        local cert_count=$(ls -1 /etc/letsencrypt/live 2>/dev/null | wc -l)
        if [ "$cert_count" -gt 0 ]; then
            all_ok+=("✓ Let's Encrypt certificates: $cert_count domain(s)")
            log_success "✓ SSL certs found"
        fi
    else
        info_items+=("ℹ Không tìm thấy Let's Encrypt certificates")
        log_info "ℹ No SSL certs"
    fi
    echo ""
    
    # 14. Kiểm tra Wings (nếu có)
    log_info "━━━ 14/15: Wings Daemon ━━━"
    if [ -f "/usr/local/bin/wings" ]; then
        info_items+=("ℹ Wings binary tồn tại")
        log_info "ℹ Wings installed"
        
        if systemctl is-active --quiet wings 2>/dev/null; then
            all_ok+=("✓ Wings service đang chạy")
            log_success "✓ Wings active"
        else
            warnings+=("⚠ Wings service không chạy")
            log_warning "⚠ Wings inactive"
        fi
    else
        info_items+=("ℹ Wings chưa cài (nếu đây là Panel-only server)")
        log_info "ℹ Wings not found"
    fi
    echo ""
    
    # 15. Kiểm tra System Info
    log_info "━━━ 15/15: System Information ━━━"
    local os_info=$(cat /etc/os-release | grep "PRETTY_NAME" | cut -d'"' -f2)
    local kernel_ver=$(uname -r)
    local uptime_info=$(uptime -p)
    
    info_items+=("ℹ OS: $os_info")
    info_items+=("ℹ Kernel: $kernel_ver")
    info_items+=("ℹ Uptime: $uptime_info")
    
    log_info "ℹ $os_info"
    log_info "ℹ Kernel: $kernel_ver"
    log_info "ℹ $uptime_info"
    echo ""
    
    # Tạo báo cáo
    generate_diagnostic_report critical_issues warnings all_ok info_items
}

# Generate diagnostic report
generate_diagnostic_report() {
    local -n crit=$1
    local -n warn=$2
    local -n ok=$3
    local -n info=$4
    
    clear
    show_banner
    
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                  DIAGNOSTIC REPORT                    ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # CRITICAL ISSUES
    if [ ${#crit[@]} -gt 0 ]; then
        echo -e "${RED}━━━ ✗ CRITICAL ISSUES (${#crit[@]}) ━━━${NC}"
        for issue in "${crit[@]}"; do
            echo -e "  ${RED}$issue${NC}"
        done
        echo ""
    fi
    
    # WARNINGS
    if [ ${#warn[@]} -gt 0 ]; then
        echo -e "${YELLOW}━━━ ⚠ WARNINGS (${#warn[@]}) ━━━${NC}"
        for warning in "${warn[@]}"; do
            echo -e "  ${YELLOW}$warning${NC}"
        done
        echo ""
    fi
    
    # ALL OK
    if [ ${#ok[@]} -gt 0 ]; then
        echo -e "${GREEN}━━━ ✓ ALL OK (${#ok[@]}) ━━━${NC}"
        for item in "${ok[@]}"; do
            echo -e "  ${GREEN}$item${NC}"
        done
        echo ""
    fi
    
    # INFO
    if [ ${#info[@]} -gt 0 ]; then
        echo -e "${BLUE}━━━ ℹ INFORMATION (${#info[@]}) ━━━${NC}"
        for item in "${info[@]}"; do
            echo -e "  ${BLUE}$item${NC}"
        done
        echo ""
    fi
    
    # SUMMARY
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}SUMMARY:${NC}"
    echo -e "  ${RED}Critical Issues: ${#crit[@]}${NC}"
    echo -e "  ${YELLOW}Warnings:        ${#warn[@]}${NC}"
    echo -e "  ${GREEN}Healthy:         ${#ok[@]}${NC}"
    echo -e "  ${BLUE}Info:            ${#info[@]}${NC}"
    echo ""
    
    # Health score
    local total=$((${#crit[@]} + ${#warn[@]} + ${#ok[@]}))
    local score=0
    if [ $total -gt 0 ]; then
        score=$(( (${#ok[@]} * 100) / total ))
    fi
    
    echo -e "${CYAN}HEALTH SCORE:${NC} "
    if [ $score -ge 80 ]; then
        echo -e "  ${GREEN}${score}% - Excellent! Panel đang hoạt động tốt${NC}"
    elif [ $score -ge 60 ]; then
        echo -e "  ${YELLOW}${score}% - Good, nhưng nên fix warnings${NC}"
    elif [ $score -ge 40 ]; then
        echo -e "  ${YELLOW}${score}% - Fair, cần khắc phục một số vấn đề${NC}"
    else
        echo -e "  ${RED}${score}% - Poor, cần fix ngay!${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BLUE}Log file: $LOG_FILE${NC}"
    echo ""
    
    # Recommendations
    if [ ${#crit[@]} -gt 0 ] || [ ${#warn[@]} -gt 0 ]; then
        echo -e "${YELLOW}💡 KHUYẾN NGHỊ:${NC}"
        echo "  - Chạy 'Auto Fix All' để tự động sửa các lỗi"
        echo "  - Hoặc chọn 'Fix từng vấn đề cụ thể' từ menu"
        echo ""
    fi
}

# Menu chính
show_menu() {
    show_banner
    echo -e "${YELLOW}Log file: $LOG_FILE${NC}"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "1) 📋 Quick Diagnostic (Chỉ kiểm tra & báo cáo)"
    echo "2) 🔍 Scan toàn bộ (Manual Fix)"
    echo "3) 🤖 Auto Fix tất cả"
    echo "4) 🔧 Fix từng vấn đề cụ thể:"
    echo "   ├─ 41) Permissions"
    echo "   ├─ 42) Database Connection"
    echo "   ├─ 43) Queue Service"
    echo "   ├─ 44) Composer Dependencies"
    echo "   ├─ 45) Cache"
    echo "   ├─ 46) Storage Permissions"
    echo "   ├─ 47) Web Server"
    echo "   ├─ 48) PHP-FPM"
    echo "   ├─ 49) Redis"
    echo "   ├─ 50) .env File"
    echo "   └─ 51) Node Modules"
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
                quick_diagnostic
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            2)
                clear
                show_banner
                run_all_checks
                show_summary
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            3)
                clear
                show_banner
                auto_fix_all
                show_summary
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            41)
                clear
                show_banner
                check_permissions
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            42)
                clear
                show_banner
                check_database
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            43)
                clear
                show_banner
                check_queue
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            44)
                clear
                show_banner
                check_composer_dependencies
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            45)
                clear
                show_banner
                check_cache
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            46)
                clear
                show_banner
                check_storage
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            47)
                clear
                show_banner
                check_webserver
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            48)
                clear
                show_banner
                check_php_fpm
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            49)
                clear
                show_banner
                check_redis
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            50)
                clear
                show_banner
                check_env_file
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            51)
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
