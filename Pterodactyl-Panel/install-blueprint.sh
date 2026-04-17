#!/bin/bash

##############################################
# Blueprint Framework Installer for Pterodactyl
# Hỗ trợ: Ubuntu 20.04/22.04/24.04, Debian 10/11/12
# Blueprint: Extension Framework cho Pterodactyl
# Version: 2.0
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

LOG_FILE="/var/log/blueprint_install_$(date +%Y%m%d_%H%M%S).log"
PTERO_DIR="/var/www/pterodactyl"
BLUEPRINT_REPO="BlueprintFramework/framework"

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

# Banner
show_banner() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════╗
║                                                       ║
║     ____  _                       _       _           ║
║    |  _ \| |                     (_)     | |          ║
║    | |_) | |_   _  ___ _ __  _ __ _ _ __ | |_         ║
║    |  _ <| | | | |/ _ \ '_ \| '__| | '_ \| __|        ║
║    | |_) | | |_| |  __/ |_) | |  | | | | | |_         ║
║    |____/|_|\__,_|\___| .__/|_|  |_|_| |_|\__|        ║
║                       | |                             ║
║                       |_|                             ║
║                                                       ║
║          Extension Framework for Pterodactyl          ║
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

# Kiểm tra hệ điều hành
check_os() {
    log "Đang kiểm tra hệ điều hành..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
        log_info "Hệ điều hành: $OS $VER"
        
        if [[ ! "$OS" =~ ^(ubuntu|debian)$ ]]; then
            log_error "Blueprint chỉ hỗ trợ Ubuntu/Debian!"
            exit 1
        fi
    else
        log_error "Không thể xác định hệ điều hành!"
        exit 1
    fi
}

# Kiểm tra Pterodactyl đã cài chưa
check_pterodactyl() {
    log "Đang kiểm tra Pterodactyl Panel..."
    
    if [ ! -d "$PTERO_DIR" ]; then
        log_error "Không tìm thấy Pterodactyl Panel tại $PTERO_DIR"
        log_error "Vui lòng cài đặt Pterodactyl Panel trước!"
        exit 1
    fi
    
    if [ ! -f "$PTERO_DIR/artisan" ]; then
        log_error "Không tìm thấy Pterodactyl artisan file!"
        exit 1
    fi
    
    log_success "✓ Đã phát hiện Pterodactyl Panel"
}

# Kiểm tra Blueprint đã cài chưa
check_blueprint_installed() {
    if [ -f "/usr/local/bin/blueprint" ] && [ -d "$PTERO_DIR/.blueprint" ]; then
        return 0
    else
        return 1
    fi
}

# Cài đặt dependencies
install_dependencies() {
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Bước 1: Cài đặt Dependencies"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    log "Đang cập nhật package list..."
    apt update 2>&1 | tee -a "$LOG_FILE"
    
    local packages=(
        "zip"
        "unzip"
        "git"
        "curl"
        "wget"
        "tar"
        "ca-certificates"
        "gnupg"
    )
    
    log "Đang cài đặt các package cần thiết..."
    for pkg in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            log_info "Cài đặt: $pkg"
            apt install -y "$pkg" 2>&1 | tee -a "$LOG_FILE"
        else
            log_info "✓ $pkg đã được cài đặt"
        fi
    done
    
    log_success "✓ Hoàn thành cài đặt dependencies"
}

# Cài đặt Node.js và Yarn
install_node_yarn() {
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Bước 2: Cài đặt Node.js và Yarn"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Kiểm tra Node.js
    if command -v node &> /dev/null; then
        local node_version=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
        log_info "Node.js version hiện tại: v$node_version"
        
        if [ "$node_version" -ge 18 ]; then
            log_success "✓ Node.js version hợp lệ"
        else
            log_warning "Node.js version < 18, cần update!"
            if confirm "Bạn có muốn update Node.js?"; then
                remove_old_nodejs
                install_nodejs
            else
                log_error "Blueprint yêu cầu Node.js >= 18!"
                exit 1
            fi
        fi
    else
        log_warning "Node.js chưa được cài đặt!"
        install_nodejs
    fi
    
    # Cài đặt Yarn
    if ! command -v yarn &> /dev/null; then
        log "Đang cài đặt Yarn..."
        npm install -g yarn 2>&1 | tee -a "$LOG_FILE"
        log_success "✓ Đã cài đặt Yarn"
    else
        log_success "✓ Yarn đã được cài đặt"
    fi
    
    # Verify versions
    log_info "Node.js: $(node -v)"
    log_info "NPM: $(npm -v)"
    log_info "Yarn: $(yarn -v)"
}

# Gỡ Node.js cũ
remove_old_nodejs() {
    log "Đang gỡ Node.js cũ..."
    apt remove --purge -y nodejs npm 2>&1 | tee -a "$LOG_FILE" || true
    apt autoremove -y 2>&1 | tee -a "$LOG_FILE" || true
    rm -rf /etc/apt/sources.list.d/nodesource.list* 2>/dev/null || true
}

# Cài đặt Node.js mới
install_nodejs() {
    log "Đang cài đặt Node.js 20.x..."
    
    # Tạo thư mục keyrings nếu chưa có
    mkdir -p /etc/apt/keyrings
    
    # Download và add GPG key
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg 2>&1 | tee -a "$LOG_FILE"
    
    # Add repository
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list 2>&1 | tee -a "$LOG_FILE"
    
    # Update và cài đặt
    apt update 2>&1 | tee -a "$LOG_FILE"
    apt install -y nodejs 2>&1 | tee -a "$LOG_FILE"
    
    log_success "✓ Đã cài đặt Node.js $(node -v)"
}

# Download Blueprint
download_blueprint() {
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Bước 3: Download Blueprint Framework"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    cd "$PTERO_DIR" || exit 1
    
    log "Đang lấy thông tin release mới nhất từ GitHub..."
    
    # Lấy URL download của latest release
    local download_url=$(curl -s "https://api.github.com/repos/$BLUEPRINT_REPO/releases/latest" | grep "browser_download_url.*zip" | cut -d '"' -f 4)
    
    if [ -z "$download_url" ]; then
        log_error "Không thể lấy URL download từ GitHub!"
        log_warning "Thử dùng phương pháp fallback..."
        download_url="https://github.com/$BLUEPRINT_REPO/releases/latest/download/blueprint.zip"
    fi
    
    log_info "Download URL: $download_url"
    
    # Xóa file cũ nếu có
    rm -f blueprint.zip 2>/dev/null || true
    
    log "Đang download Blueprint..."
    if ! wget -q --show-progress "$download_url" -O blueprint.zip 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Không thể download Blueprint!"
        exit 1
    fi
    
    # Kiểm tra file đã download
    if [ ! -f "blueprint.zip" ]; then
        log_error "File blueprint.zip không tồn tại!"
        exit 1
    fi
    
    log_info "Kích thước file: $(du -h blueprint.zip | cut -f1)"
    log_success "✓ Download thành công"
}

# Cài đặt Blueprint
install_blueprint() {
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Bước 4: Cài đặt Blueprint Framework"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    cd "$PTERO_DIR" || exit 1
    
    log "Đang giải nén Blueprint..."
    if ! unzip -o blueprint.zip 2>&1 | tee -a "$LOG_FILE"; then
        log_error "Không thể giải nén Blueprint!"
        exit 1
    fi
    
    log_success "✓ Giải nén thành công"
    
    # Xóa file zip
    rm -f blueprint.zip 2>/dev/null || true
    
    # Kiểm tra file blueprint.sh
    if [ ! -f "blueprint.sh" ]; then
        log_error "Không tìm thấy blueprint.sh!"
        exit 1
    fi
    
    # Set permissions
    log "Đang cấu hình permissions..."
    chmod +x blueprint.sh 2>&1 | tee -a "$LOG_FILE"
    
    # Install dependencies cho panel
    log "Đang cài đặt dependencies cho Pterodactyl Panel..."
    cd "$PTERO_DIR" || exit 1
    
    log_info "Chạy: yarn"
    yarn 2>&1 | tee -a "$LOG_FILE"
    
    log_info "Đang chạy Blueprint installer..."
    bash blueprint.sh 2>&1 | tee -a "$LOG_FILE"
    
    log_success "✓ Blueprint đã được cài đặt"
}

# Verify installation
verify_installation() {
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "Bước 5: Kiểm tra cài đặt"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local all_good=true
    
    # Kiểm tra blueprint command
    if command -v blueprint &> /dev/null; then
        log_success "✓ Blueprint command đã được cài đặt"
        
        # Get version
        local version=$(blueprint -v 2>/dev/null || echo "unknown")
        log_info "Blueprint version: $version"
    else
        log_error "✗ Blueprint command không tồn tại!"
        all_good=false
    fi
    
    # Kiểm tra thư mục Blueprint
    if [ -d "$PTERO_DIR/.blueprint" ]; then
        log_success "✓ Blueprint directory tồn tại"
    else
        log_error "✗ Blueprint directory không tồn tại!"
        all_good=false
    fi
    
    # Kiểm tra các file quan trọng
    local files=(
        "/usr/local/bin/blueprint"
        "$PTERO_DIR/.blueprint/extensions"
    )
    
    for file in "${files[@]}"; do
        if [ -e "$file" ]; then
            log_success "✓ Found: $file"
        else
            log_warning "✗ Missing: $file"
        fi
    done
    
    if [ "$all_good" = true ]; then
        log_success "✓ Verification hoàn tất - Blueprint đã sẵn sàng!"
        return 0
    else
        log_error "✗ Verification thất bại - Có lỗi xảy ra!"
        return 1
    fi
}

# Gỡ cài đặt Blueprint
uninstall_blueprint() {
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "GỠ CÀI ĐẶT BLUEPRINT FRAMEWORK"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if ! check_blueprint_installed; then
        log_warning "Blueprint chưa được cài đặt!"
        return
    fi
    
    log_warning "CẢNH BÁO: Bước này sẽ gỡ Blueprint và TẤT CẢ extensions!"
    
    if ! confirm "Bạn chắc chắn muốn gỡ Blueprint?"; then
        log "Đã hủy"
        return
    fi
    
    cd "$PTERO_DIR" || exit 1
    
    # Gỡ bằng Blueprint command nếu có
    if command -v blueprint &> /dev/null; then
        log "Đang gỡ Blueprint bằng blueprint command..."
        blueprint -remove 2>&1 | tee -a "$LOG_FILE" || true
    fi
    
    # Xóa các file và thư mục
    log "Đang xóa các file Blueprint..."
    
    rm -rf "$PTERO_DIR/.blueprint" 2>&1 | tee -a "$LOG_FILE" || true
    rm -f /usr/local/bin/blueprint 2>&1 | tee -a "$LOG_FILE" || true
    rm -f "$PTERO_DIR/blueprint.sh" 2>&1 | tee -a "$LOG_FILE" || true
    
    # Rebuild panel
    log "Đang rebuild Pterodactyl Panel..."
    cd "$PTERO_DIR" || exit 1
    
    php artisan view:clear 2>&1 | tee -a "$LOG_FILE" || true
    php artisan config:clear 2>&1 | tee -a "$LOG_FILE" || true
    
    log "Đang rebuild assets..."
    yarn install --production 2>&1 | tee -a "$LOG_FILE" || true
    yarn build:production 2>&1 | tee -a "$LOG_FILE" || true
    
    log_success "✓ Đã gỡ Blueprint"
    
    # Verify removal
    if [ ! -f "/usr/local/bin/blueprint" ] && [ ! -d "$PTERO_DIR/.blueprint" ]; then
        log_success "✓ Verification: Blueprint đã được gỡ hoàn toàn"
    else
        log_warning "Một số file còn sót lại!"
        
        if confirm "Bạn có muốn xóa các file còn sót không?"; then
            rm -rf "$PTERO_DIR/.blueprint" 2>/dev/null || true
            rm -f /usr/local/bin/blueprint 2>/dev/null || true
            log_success "✓ Đã xóa file còn sót"
        fi
    fi
}

# Update Blueprint
update_blueprint() {
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "UPDATE BLUEPRINT FRAMEWORK"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if ! check_blueprint_installed; then
        log_error "Blueprint chưa được cài đặt!"
        return
    fi
    
    cd "$PTERO_DIR" || exit 1
    
    if command -v blueprint &> /dev/null; then
        log "Đang update Blueprint..."
        blueprint -upgrade 2>&1 | tee -a "$LOG_FILE"
        log_success "✓ Blueprint đã được update"
    else
        log_error "Blueprint command không tồn tại!"
    fi
}

# Show usage
show_usage() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║        HƯỚNG DẪN SỬ DỤNG BLUEPRINT         ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}📦 Các lệnh phổ biến:${NC}"
    echo ""
    echo -e "  ${YELLOW}blueprint -i <extension>${NC}    Cài đặt extension"
    echo -e "  ${YELLOW}blueprint -r <extension>${NC}    Gỡ extension"
    echo -e "  ${YELLOW}blueprint -list${NC}              Danh sách extensions"
    echo -e "  ${YELLOW}blueprint -upgrade${NC}           Update Blueprint"
    echo -e "  ${YELLOW}blueprint -v${NC}                 Xem version"
    echo -e "  ${YELLOW}blueprint -help${NC}              Xem help đầy đủ"
    echo ""
    echo -e "${GREEN}🎨 Admin Panel:${NC}"
    echo "  • Đăng nhập Admin Area"
    echo "  • Vào menu 'Blueprint'"
    echo "  • Tại đây bạn có thể quản lý extensions và themes"
    echo ""
    echo -e "${GREEN}📥 Cài đặt Extension:${NC}"
    echo "  1. Download file .blueprint từ nguồn tin cậy"
    echo "  2. Upload file vào /var/www/pterodactyl"
    echo "  3. Chạy: blueprint -i <tên-file>"
    echo "     (không cần đuôi .blueprint)"
    echo ""
    echo -e "${GREEN}🔗 Tài liệu & Extensions:${NC}"
    echo "  • Tài liệu: https://blueprint.zip/docs"
    echo "  • Extensions: https://blueprint.zip/browse"
    echo "  • Discord: https://discord.gg/CUwHwv6xRe"
    echo ""
}

# Menu chính
show_menu() {
    show_banner
    echo -e "${YELLOW}Log file: $LOG_FILE${NC}"
    echo ""
    
    if check_blueprint_installed; then
        echo -e "${GREEN}● Status: Blueprint đã được cài đặt${NC}"
        if command -v blueprint &> /dev/null; then
            local ver=$(blueprint -v 2>/dev/null | head -n1 || echo "unknown")
            echo -e "${BLUE}  Version: $ver${NC}"
        fi
    else
        echo -e "${RED}● Status: Blueprint chưa được cài đặt${NC}"
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "1) Cài đặt Blueprint"
    echo "2) Gỡ cài đặt Blueprint"
    echo "3) Update Blueprint"
    echo "4) Kiểm tra trạng thái"
    echo "5) Hướng dẫn sử dụng"
    echo "0) Thoát"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Main installation
main_install() {
    show_banner
    log "Bắt đầu cài đặt Blueprint Framework"
    log "Log file: $LOG_FILE"
    echo ""
    
    check_os
    check_pterodactyl
    
    if check_blueprint_installed; then
        log_warning "Blueprint đã được cài đặt!"
        if confirm "Bạn có muốn cài đặt lại không?"; then
            uninstall_blueprint
            echo ""
            log "Tiếp tục cài đặt mới..."
        else
            log "Đã hủy"
            return
        fi
    fi
    
    install_dependencies
    install_node_yarn
    download_blueprint
    install_blueprint
    
    echo ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if verify_installation; then
        echo ""
        log_success "🎉 CÀI ĐẶT BLUEPRINT THÀNH CÔNG! 🎉"
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo -e "${GREEN}✓ Blueprint đã sẵn sàng sử dụng!${NC}"
        echo ""
        echo -e "${YELLOW}Bước tiếp theo:${NC}"
        echo "1. Truy cập Admin Panel của Pterodactyl"
        echo "2. Vào menu 'Blueprint' để quản lý extensions"
        echo "3. Download extensions từ: https://blueprint.zip/browse"
        echo ""
        echo -e "${CYAN}Hoặc sử dụng lệnh:${NC} blueprint -help"
        echo ""
    else
        log_error "Cài đặt không thành công!"
        log_error "Vui lòng kiểm tra log tại: $LOG_FILE"
    fi
}

# Check status
check_status() {
    show_banner
    log "Đang kiểm tra trạng thái Blueprint..."
    echo ""
    
    if check_blueprint_installed; then
        log_success "✓ Blueprint đã được cài đặt"
        
        if command -v blueprint &> /dev/null; then
            echo ""
            echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${GREEN}Blueprint Information:${NC}"
            echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            blueprint -v 2>/dev/null || echo "Không thể lấy version"
            
            echo ""
            echo -e "${GREEN}Installed Extensions:${NC}"
            echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            blueprint -list 2>/dev/null || echo "Không có extension nào"
            
            echo ""
            echo -e "${GREEN}Files Status:${NC}"
            echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            [ -f "/usr/local/bin/blueprint" ] && echo "✓ /usr/local/bin/blueprint" || echo "✗ /usr/local/bin/blueprint"
            [ -d "$PTERO_DIR/.blueprint" ] && echo "✓ $PTERO_DIR/.blueprint" || echo "✗ $PTERO_DIR/.blueprint"
            [ -d "$PTERO_DIR/.blueprint/extensions" ] && echo "✓ $PTERO_DIR/.blueprint/extensions" || echo "✗ $PTERO_DIR/.blueprint/extensions"
        fi
    else
        log_warning "Blueprint chưa được cài đặt"
        echo ""
        echo -e "${YELLOW}Để cài đặt Blueprint, chọn option 1 từ menu chính${NC}"
    fi
    
    echo ""
    read -p "Nhấn Enter để tiếp tục..."
}

# Main
main() {
    check_root
    
    while true; do
        show_menu
        read -p "Chọn tùy chọn [0-5]: " choice
        
        case $choice in
            1)
                main_install
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            2)
                uninstall_blueprint
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            3)
                update_blueprint
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            4)
                check_status
                ;;
            5)
                show_usage
                read -p "Nhấn Enter để tiếp tục..."
                ;;
            0)
                log "Thoát script"
                echo ""
                echo -e "${GREEN}Cảm ơn bạn đã sử dụng Blueprint Installer!${NC}"
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
