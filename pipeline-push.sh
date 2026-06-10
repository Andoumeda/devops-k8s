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

DOCKERHUB_USER="${DOCKERHUB_USER:-}"
BACKEND_IMAGE="${BACKEND_IMAGE:-todo-backend}"
FRONTEND_IMAGE="${FRONTEND_IMAGE:-todo-frontend}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

echo "=== Pipeline 2: Push a DockerHub ==="

echo "1. Verificando Docker..."
if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: Docker no esta instalado o no esta en el PATH"
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker no esta corriendo o tu usuario no tiene permisos para usarlo"
    exit 1
fi

echo "2. Verificando que las imagenes existen localmente..."
docker image inspect "$BACKEND_IMAGE:$IMAGE_TAG" >/dev/null 2>&1 || { echo "ERROR: La imagen '$BACKEND_IMAGE:$IMAGE_TAG' no existe. Ejecuta pipeline-build.sh primero."; exit 1; }
docker image inspect "$FRONTEND_IMAGE:$IMAGE_TAG" >/dev/null 2>&1 || { echo "ERROR: La imagen '$FRONTEND_IMAGE:$IMAGE_TAG' no existe. Ejecuta pipeline-build.sh primero."; exit 1; }

echo "3. Login a DockerHub..."

# Si no vienen por variable de entorno, pedir interactivamente
if test -z "${DOCKERHUB_USER:-}"; then
    read -rp "Usuario de DockerHub: " DOCKERHUB_USER
fi

if test -z "${DOCKERHUB_TOKEN:-}"; then
    read -rsp "Contraseña/Token de DockerHub: " DOCKERHUB_TOKEN
    echo
fi

if test -z "$DOCKERHUB_USER" || test -z "$DOCKERHUB_TOKEN"; then
    echo "ERROR: Debes proporcionar usuario y contraseña/token de DockerHub"
    exit 1
fi

printf '%s' "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USER" --password-stdin

echo "4. Tag Backend..."
docker tag "$BACKEND_IMAGE:$IMAGE_TAG" "$DOCKERHUB_USER/$BACKEND_IMAGE:$IMAGE_TAG"

echo "5. Tag Frontend..."
docker tag "$FRONTEND_IMAGE:$IMAGE_TAG" "$DOCKERHUB_USER/$FRONTEND_IMAGE:$IMAGE_TAG"

echo "6. Push Backend..."
docker push "$DOCKERHUB_USER/$BACKEND_IMAGE:$IMAGE_TAG"

echo "7. Push Frontend..."
docker push "$DOCKERHUB_USER/$FRONTEND_IMAGE:$IMAGE_TAG"

echo "=== Push completado ==="
echo "Backend: $DOCKERHUB_USER/$BACKEND_IMAGE:$IMAGE_TAG"
echo "Frontend: $DOCKERHUB_USER/$FRONTEND_IMAGE:$IMAGE_TAG"
