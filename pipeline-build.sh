#!/bin/bash
set -euo pipefail

# Auto-abrir en terminal si se ejecuta con doble clic (sin TTY)
if [ ! -t 0 ] && [ ! -t 1 ]; then
    SCRIPT_PATH="$(readlink -f "$0")"
    for terminal in gnome-terminal xfce4-terminal mate-terminal konsole alacritty kitty xterm; do
        if command -v "$terminal" >/dev/null 2>&1; then
            case "$terminal" in
                gnome-terminal|xfce4-terminal|mate-terminal)
                    exec "$terminal" -- bash -c "\"$SCRIPT_PATH\"; exec bash"
                    ;;
                konsole)
                    exec "$terminal" --new-tab -e bash -c "\"$SCRIPT_PATH\"; exec bash"
                    ;;
                *)
                    exec "$terminal" -e bash -c "\"$SCRIPT_PATH\"; exec bash"
                    ;;
            esac
        fi
    done
    echo "ERROR: No se encontró un emulador de terminal. Ejecuta este script desde una terminal."
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_IMAGE="${BACKEND_IMAGE:-todo-backend}"
FRONTEND_IMAGE="${FRONTEND_IMAGE:-todo-frontend}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

require_file() {
    if ! test -f "$1"; then
        echo "ERROR: Falta el archivo requerido: $1"
        exit 1
    fi
}

echo "=== Pipeline 1: Compilacion ==="

echo "1. Verificando Docker..."
if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: Docker no esta instalado o no esta en el PATH"
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker no esta corriendo o tu usuario no tiene permisos para usarlo"
    exit 1
fi

echo "2. Verificando archivos del backend..."
require_file "$SCRIPT_DIR/backend/Dockerfile"
require_file "$SCRIPT_DIR/backend/package.json"
require_file "$SCRIPT_DIR/backend/index.js"

echo "3. Verificando archivos del frontend..."
require_file "$SCRIPT_DIR/frontend/Dockerfile"
require_file "$SCRIPT_DIR/frontend/index.html"
require_file "$SCRIPT_DIR/frontend/app.js"
require_file "$SCRIPT_DIR/frontend/style.css"

echo "4. Build Docker Images..."
docker build -t "$BACKEND_IMAGE:$IMAGE_TAG" "$SCRIPT_DIR/backend"
docker build -t "$FRONTEND_IMAGE:$IMAGE_TAG" "$SCRIPT_DIR/frontend"

echo "=== Build completado ==="
echo "Backend: $BACKEND_IMAGE:$IMAGE_TAG"
echo "Frontend: $FRONTEND_IMAGE:$IMAGE_TAG"
