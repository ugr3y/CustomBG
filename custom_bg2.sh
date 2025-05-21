#!/usr/bin/env bash

set -euo pipefail

IMAGE_NAME="loginbg.png"
DEST_IMAGE_PATH="/usr/share/gnome-shell/${IMAGE_NAME}"
CUSTOM_CSS="/usr/share/gnome-shell/gnome-shell.css"
GRESOURCE_XML="/usr/share/gnome-shell/gnome-shell-theme.gresource.xml"
GRESOURCE_COMPILED="/usr/share/gnome-shell/gnome-shell-theme.gresource"

check_root() {
    [ "$(id -u)" -eq 0 ] || { echo "Run as root"; exit 1; }
}

prepare_image() {
    cp "${IMAGE_NAME}" "${DEST_IMAGE_PATH}"
    chmod 644 "${DEST_IMAGE_PATH}"
}

create_css() {
    cat > "${CUSTOM_CSS}" <<EOF
/* Minimal GDM CSS */
#lockDialogGroup {
    background: url("file://${DEST_IMAGE_PATH}") no-repeat center center;
    background-size: cover;
}
EOF
}

create_xml() {
    cat > "${GRESOURCE_XML}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<gresources>
  <gresource prefix="/org/gnome/shell/theme">
    <file>gnome-shell.css</file>
  </gresource>
</gresources>
EOF
}

compile_gresource() {
    glib-compile-resources --target="${GRESOURCE_COMPILED}" --sourcedir="/usr/share/gnome-shell" "${GRESOURCE_XML}"
    chmod 644 "${GRESOURCE_COMPILED}"
}

backup_original() {
    if [ ! -f "${GRESOURCE_COMPILED}.backup" ]; then
        cp "${GRESOURCE_COMPILED}" "${GRESOURCE_COMPILED}.backup"
    fi
}

main() {
    check_root
    prepare_image
    create_css
    create_xml
    backup_original
    compile_gresource
    echo "✔ Background set. Reboot or restart GDM with: sudo systemctl restart gdm3"
}

main
