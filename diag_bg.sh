#!/usr/bin/env bash

# GDM Login Background Diagnostic Script
# Run this script to diagnose issues with custom GDM login backgrounds

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This diagnostic script must be run as root (use sudo)"
        exit 1
    fi
}

# Configuration matching your script
BG_ASSETS_DIR="/usr/local/share/bg-assets"
LOGIN_BG_DEST_PATH="${BG_ASSETS_DIR}/loginbg.png"
CUSTOM_GDM_SKIN_DIR="/usr/local/share/custom-gdm-skin"
CUSTOM_CSS_PATH="${CUSTOM_GDM_SKIN_DIR}/custom-gdm.css"
COMPILED_GRESOURCE_PATH="${CUSTOM_GDM_SKIN_DIR}/custom-gdm-theme.gresource"
LINK_PATH="/usr/share/gnome-shell/gnome-shell-theme.gresource"

echo "========================================"
echo "GDM Login Background Diagnostic Report"
echo "========================================"
echo

# 1. Check Ubuntu version and GNOME Shell version
info "Checking system versions..."
echo "Ubuntu version: $(lsb_release -d | cut -f2)"
echo "GNOME Shell version: $(gnome-shell --version 2>/dev/null || echo 'Not available')"
echo

# 2. Check if files exist
info "Checking required files..."
files_to_check=(
    "$LOGIN_BG_DEST_PATH"
    "$CUSTOM_CSS_PATH"
    "$COMPILED_GRESOURCE_PATH"
    "$LINK_PATH"
)

for file in "${files_to_check[@]}"; do
    if [ -f "$file" ]; then
        success "✓ $file exists"
        ls -la "$file"
    else
        error "✗ $file NOT FOUND"
    fi
done
echo

# 3. Check update-alternatives configuration
info "Checking update-alternatives configuration..."
if update-alternatives --display gnome-shell-theme.gresource &>/dev/null; then
    update-alternatives --display gnome-shell-theme.gresource
else
    error "No alternatives configured for gnome-shell-theme.gresource"
fi
echo

# 4. Check what the symlink points to
info "Checking current GDM theme symlink..."
if [ -L "$LINK_PATH" ]; then
    target=$(readlink -f "$LINK_PATH")
    success "GDM theme symlink points to: $target"
    if [ "$target" = "$COMPILED_GRESOURCE_PATH" ]; then
        success "✓ Symlink correctly points to custom theme"
    else
        warning "⚠ Symlink points to different theme: $target"
    fi
else
    if [ -f "$LINK_PATH" ]; then
        warning "GDM theme is a regular file, not managed by alternatives"
    else
        error "GDM theme file/symlink not found"
    fi
fi
echo

# 5. Check CSS content and validate paths
info "Checking custom CSS content..."
if [ -f "$CUSTOM_CSS_PATH" ]; then
    echo "CSS content:"
    cat "$CUSTOM_CSS_PATH"
    echo
    
    # Extract background image path from CSS
    bg_path=$(grep -o "file://[^']*" "$CUSTOM_CSS_PATH" | head -1 | sed 's/file:\/\///')
    if [ -f "$bg_path" ]; then
        success "✓ Background image referenced in CSS exists: $bg_path"
    else
        error "✗ Background image referenced in CSS not found: $bg_path"
    fi
else
    error "Custom CSS file not found"
fi
echo

# 6. Test gresource content
info "Checking compiled gresource content..."
if [ -f "$COMPILED_GRESOURCE_PATH" ]; then
    if command -v gresource >/dev/null 2>&1; then
        echo "Resources in compiled gresource:"
        gresource list "$COMPILED_GRESOURCE_PATH" 2>/dev/null || echo "Failed to list gresource contents"
        echo
        echo "CSS content from gresource:"
        gresource extract "$COMPILED_GRESOURCE_PATH" /org/gnome/shell/theme/gnome-shell.css 2>/dev/null || echo "Failed to extract CSS from gresource"
    else
        warning "gresource command not available for detailed inspection"
    fi
else
    error "Compiled gresource file not found"
fi
echo

# 7. Check GDM service status
info "Checking GDM service status..."
systemctl status gdm3 --no-pager -l || systemctl status gdm --no-pager -l || echo "GDM service status unavailable"
echo

# 8. Check for common issues
info "Checking for common issues..."

# Check if background image is accessible
if [ -f "$LOGIN_BG_DEST_PATH" ]; then
    if [ -r "$LOGIN_BG_DEST_PATH" ]; then
        success "✓ Background image is readable"
    else
        error "✗ Background image exists but is not readable"
    fi
    
    # Check image format
    file_type=$(file "$LOGIN_BG_DEST_PATH" 2>/dev/null | cut -d: -f2)
    echo "Background image type: $file_type"
    
    # Check file size
    file_size=$(du -h "$LOGIN_BG_DEST_PATH" | cut -f1)
    echo "Background image size: $file_size"
fi

# Check directory permissions
for dir in "$BG_ASSETS_DIR" "$CUSTOM_GDM_SKIN_DIR"; do
    if [ -d "$dir" ]; then
        perms=$(stat -c "%a" "$dir")
        if [ "$perms" -ge 755 ]; then
            success "✓ Directory $dir has good permissions ($perms)"
        else
            warning "⚠ Directory $dir may have insufficient permissions ($perms)"
        fi
    fi
done
echo

# 9. Suggest alternative CSS selectors to try
info "Alternative CSS selectors to try if current one doesn't work:"
echo "Instead of #lockDialogGroup, try one of these:"
echo "  • .login-dialog"
echo "  • .unlock-dialog" 
echo "  • .screen-shield-background"
echo "  • StageWidget (for older versions)"
echo "  • .gdm-dialog"
echo

# 10. Generate a test CSS with multiple selectors
info "Generating test CSS with multiple selectors..."
test_css_path="${CUSTOM_GDM_SKIN_DIR}/test-gdm.css"
cat > "$test_css_path" << 'EOF'
/* Test CSS with multiple selectors for GDM background */
@import url("file:///usr/share/gnome-shell/theme/Yaru/gnome-shell.css");

/* Try multiple selectors that might work */
#lockDialogGroup,
.login-dialog,
.unlock-dialog,
.screen-shield-background,
.gdm-dialog,
StageWidget {
    background: url('file:///usr/local/share/bg-assets/loginbg.png') !important;
    background-size: cover !important;
    background-repeat: no-repeat !important;
    background-position: center center !important;
}

/* Additional specific selectors */
.screen-shield-background .screen-shield-contents,
.unlock-dialog .modal-dialog,
.login-dialog .modal-dialog {
    background: url('file:///usr/local/share/bg-assets/loginbg.png') !important;
    background-size: cover !important;
    background-repeat: no-repeat !important;
    background-position: center center !important;
}
EOF

success "Test CSS generated at: $test_css_path"
echo "You can try using this test CSS by:"
echo "1. Copying it over your current CSS: cp '$test_css_path' '$CUSTOM_CSS_PATH'"
echo "2. Recompiling the gresource and restarting GDM"
echo

echo "========================================"
echo "Diagnostic complete!"
echo "========================================"
echo
echo "If the files look correct, try these steps:"
echo "1. Test with the alternative CSS selectors above"
echo "2. Ensure the background image is a standard PNG/JPG format"
echo "3. Check GNOME Shell extensions aren't interfering"
echo "4. Try logging out and back in instead of just restarting GDM"
echo "5. Check /var/log/gdm3/ for any error messages"