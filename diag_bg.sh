#!/usr/bin/env bash

# GDM Theme Detective - Find out what's really happening with GDM themes

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

echo "============================================="
echo "GDM Theme Detective - Finding the Real Issue"
echo "============================================="
echo

# 1. Check what GDM is actually using
info "1. Checking GDM configuration and theme paths..."

# Check GDM configuration files
gdm_configs=(
    "/etc/gdm3/greeter.dconf-defaults"
    "/etc/gdm3/custom.conf"
    "/etc/dconf/db/gdm.d/"
    "/var/lib/gdm3/.config/dconf/user"
)

for config in "${gdm_configs[@]}"; do
    if [ -e "$config" ]; then
        success "Found: $config"
        if [ -f "$config" ]; then
            echo "Content preview:"
            head -20 "$config" 2>/dev/null | sed 's/^/  /'
        else
            echo "Directory contents:"
            ls -la "$config" 2>/dev/null | sed 's/^/  /'
        fi
        echo
    else
        warning "Not found: $config"
    fi
done

# 2. Check what theme files actually exist
info "2. Checking theme file locations..."

theme_locations=(
    "/usr/share/gnome-shell/gnome-shell-theme.gresource"
    "/usr/share/gnome-shell/theme/Yaru/gnome-shell.css"
    "/usr/share/themes/Yaru/gnome-shell/gnome-shell.css"
    "/usr/local/share/themes/"
    "/home/$(logname)/.themes/" 2>/dev/null || true
    "/home/$(logname)/.local/share/themes/" 2>/dev/null || true
)

for location in "${theme_locations[@]}"; do
    if [ -e "$location" ]; then
        if [ -f "$location" ]; then
            success "File exists: $location"
            ls -la "$location"
            if [ -L "$location" ]; then
                echo "  → Symlink points to: $(readlink -f "$location")"
            fi
        else
            success "Directory exists: $location"
            ls -la "$location" 2>/dev/null | head -10 | sed 's/^/  /'
        fi
    else
        warning "Not found: $location"
    fi
    echo
done

# 3. Check if there are any GNOME Shell extensions affecting themes
info "3. Checking for GNOME Shell extensions that might affect themes..."

# System extensions
if [ -d "/usr/share/gnome-shell/extensions" ]; then
    echo "System extensions:"
    ls /usr/share/gnome-shell/extensions/ | grep -E "(theme|user|gdm)" | sed 's/^/  /' || echo "  None found"
fi

# User extensions (check common users)
for user_home in /home/*; do
    if [ -d "$user_home/.local/share/gnome-shell/extensions" ]; then
        echo "Extensions for user $(basename "$user_home"):"
        ls "$user_home/.local/share/gnome-shell/extensions/" | grep -E "(theme|user|gdm)" | sed 's/^/  /' || echo "  None found"
    fi
done
echo

# 4. Check GDM process and environment
info "4. Checking GDM process information..."

if pgrep -f gdm >/dev/null; then
    echo "GDM processes:"
    ps aux | grep -E "(gdm|gnome-shell)" | grep -v grep | sed 's/^/  /'
else
    warning "No GDM processes found"
fi
echo

# 5. Check dconf settings for GDM
info "5. Checking dconf database for GDM..."

if command -v dconf >/dev/null; then
    echo "GDM dconf settings:"
    # Try to read GDM user settings
    if [ -f "/var/lib/gdm3/.config/dconf/user" ]; then
        echo "GDM dconf database exists"
        # Try to dump settings (might need to run as gdm user)
        sudo -u gdm dconf dump / 2>/dev/null | head -20 | sed 's/^/  /' || echo "  Could not read GDM dconf settings"
    else
        echo "  No GDM dconf database found"
    fi
else
    warning "dconf command not available"
fi
echo

# 6. Check for Ubuntu-specific theme overrides
info "6. Checking Ubuntu-specific configurations..."

ubuntu_configs=(
    "/usr/share/glib-2.0/schemas/10_ubuntu-settings.gschema.override"
    "/usr/share/glib-2.0/schemas/ubuntu.gschema.override"
    "/etc/dconf/db/local.d/"
)

for config in "${ubuntu_configs[@]}"; do
    if [ -e "$config" ]; then
        success "Found: $config"
        if [ -f "$config" ]; then
            echo "Content (looking for theme settings):"
            grep -i -A5 -B5 "theme\|gtk\|shell" "$config" 2>/dev/null | sed 's/^/  /' || echo "  No theme-related settings found"
        fi
        echo
    fi
done

# 7. Check what's actually in the gresource file
info "7. Analyzing the actual gresource theme file..."

gresource_file=""
if [ -f "/usr/share/gnome-shell/gnome-shell-theme.gresource" ]; then
    gresource_file="/usr/share/gnome-shell/gnome-shell-theme.gresource"
elif [ -L "/usr/share/gnome-shell/gnome-shell-theme.gresource" ]; then
    gresource_file=$(readlink -f "/usr/share/gnome-shell/gnome-shell-theme.gresource")
fi

if [ -n "$gresource_file" ] && [ -f "$gresource_file" ]; then
    success "Found gresource file: $gresource_file"
    
    if command -v gresource >/dev/null; then
        echo "Contents of gresource file:"
        gresource list "$gresource_file" | sed 's/^/  /'
        echo
        
        echo "CSS content preview:"
        gresource extract "$gresource_file" /org/gnome/shell/theme/gnome-shell.css 2>/dev/null | head -30 | sed 's/^/  /' || echo "  Could not extract CSS"
    else
        warning "gresource command not available for inspection"
    fi
else
    error "No gresource theme file found!"
fi
echo

# 8. Test different approaches
info "8. Testing different theme modification approaches..."

echo "Let's test if we can modify themes in different locations:"

# Test 1: Try modifying gsettings for the gdm user
echo "Test 1: Checking gsettings approach..."
if sudo -u gdm gsettings get org.gnome.shell.extensions.user-theme name 2>/dev/null; then
    echo "  User theme extension is available for GDM user"
    current_theme=$(sudo -u gdm gsettings get org.gnome.shell.extensions.user-theme name 2>/dev/null || echo "none")
    echo "  Current theme: $current_theme"
else
    echo "  User theme extension not available or not accessible"
fi

# Test 2: Check if we can create a theme in the themes directory
echo "Test 2: Checking if we can create themes in standard locations..."
for theme_dir in "/usr/share/themes" "/usr/local/share/themes"; do
    if [ -d "$theme_dir" ]; then
        success "Can use theme directory: $theme_dir"
        ls -la "$theme_dir" | head -5 | sed 's/^/  /'
    else
        warning "Theme directory doesn't exist: $theme_dir"
    fi
done
echo

# 9. Generate solutions based on findings
info "9. Recommended solutions based on system analysis..."

echo "Based on the analysis above, here are the most likely solutions:"
echo
echo "SOLUTION A: Create a proper theme in /usr/share/themes/"
echo "SOLUTION B: Use dconf to override GDM settings"  
echo "SOLUTION C: Modify the existing gresource with correct CSS"
echo "SOLUTION D: Use gsettings with user-theme extension"
echo
echo "Which solution would you like me to generate? (A/B/C/D): "
read -r solution_choice

case "$solution_choice" in
    [Aa])
        echo "Generating theme-based solution..."
        generate_theme_solution
        ;;
    [Bb])
        echo "Generating dconf-based solution..."
        generate_dconf_solution
        ;;
    [Cc])
        echo "Generating gresource fix solution..."
        generate_gresource_solution
        ;;
    [Dd])
        echo "Generating gsettings-based solution..."
        generate_gsettings_solution
        ;;
    *)
        echo "Invalid choice. Run the script again to select a solution."
        ;;
esac

generate_theme_solution() {
    cat > "/tmp/gdm_theme_solution.sh" << 'EOF'
#!/bin/bash
# Theme-based GDM background solution

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
BG_IMAGE="$SCRIPT_DIR/loginbg.png"
THEME_NAME="custom-gdm-theme"
THEME_DIR="/usr/share/themes/$THEME_NAME"

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo $0"
    exit 1
fi

if [ ! -f "$BG_IMAGE" ]; then
    echo "Put loginbg.png in the same directory as this script"
    exit 1
fi

# Create theme structure
mkdir -p "$THEME_DIR/gnome-shell"
cp "$BG_IMAGE" "$THEME_DIR/gnome-shell/"

# Create theme CSS
cat > "$THEME_DIR/gnome-shell/gnome-shell.css" << 'EOCSS'
@import url("resource:///org/gnome/shell/theme/gnome-shell.css");

#lockDialogGroup,
.login-dialog,
.unlock-dialog,
.screen-shield-background,
.screen-shield {
    background: url("loginbg.png") !important;
    background-size: cover !important;
    background-repeat: no-repeat !important;
    background-position: center center !important;
}
EOCSS

# Set permissions
chmod -R 755 "$THEME_DIR"

# Enable user-theme extension for GDM
sudo -u gdm dbus-launch gsettings set org.gnome.shell enabled-extensions "['user-theme@gnome-shell-extensions.gnome.org']"
sudo -u gdm dbus-launch gsettings set org.gnome.shell.extensions.user-theme name "$THEME_NAME"

echo "Theme installed. Restart GDM to see changes."
EOF
    
    chmod +x "/tmp/gdm_theme_solution.sh"
    success "Solution A script created at /tmp/gdm_theme_solution.sh"
}

generate_dconf_solution() {
    cat > "/tmp/gdm_dconf_solution.sh" << 'EOF'
#!/bin/bash
# dconf-based GDM background solution

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root: sudo $0"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
BG_IMAGE="$SCRIPT_DIR/loginbg.png"
DEST_IMAGE="/usr/share/pixmaps/gdm-background.png"

if [ ! -f "$BG_IMAGE" ]; then
    echo "Put loginbg.png in the same directory as this script"
    exit 1
fi

# Copy background
cp "$BG_IMAGE" "$DEST_IMAGE"
chmod 644 "$DEST_IMAGE"

# Create dconf override
mkdir -p /etc/dconf/db/gdm.d/
cat > /etc/dconf/db/gdm.d/01-background << EOF
[org/gnome/desktop/background]
picture-uri='file://$DEST_IMAGE'
picture-options='zoom'
primary-color='#000000'

[org/gnome/desktop/screensaver] 
picture-uri='file://$DEST_IMAGE'
picture-options='zoom'
primary-color='#000000'
EOF

# Update dconf database
dconf update

echo "dconf background set. Restart GDM to see changes."
EOF
    
    chmod +x "/tmp/gdm_dconf_solution.sh"
    success "Solution B script created at /tmp/gdm_dconf_solution.sh"
}

generate_gresource_solution() {
    echo "This will recreate your gresource approach with debugging..."
    echo "Check the detective output above first to see what went wrong."
}

generate_gsettings_solution() {
    echo "This requires the user-theme extension to be installed."
    echo "Check if gnome-shell-extensions is installed first."
}

main() {
    check_root
    # All the diagnostic functions are called inline above
    echo "Analysis complete. Check the output above for clues."
}

main