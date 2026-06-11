#!/bin/bash
set -e

echo "=========================================="
echo "  INSTALADOR PIPELINE DEVOPS KUBERNETES"
echo "=========================================="

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ==========================================
# DETECCIÓN DE DISTRIBUCIÓN
# ==========================================
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID="$ID"
        DISTRO_LIKE="${ID_LIKE:-$ID}"
    else
        DISTRO_ID="unknown"
        DISTRO_LIKE="unknown"
    fi

    case "$DISTRO_LIKE" in
        *arch*|*garuda*|*manjaro*|*endeavour*)
            PKG_MANAGER="pacman"
            PKG_UPDATE="sudo pacman -Sy"
            PKG_INSTALL="sudo pacman -S --noconfirm --needed"
            log "Distribución detectada: $DISTRO_ID (Arch-based, usando pacman)"
            ;;
        *debian*|*ubuntu*|*)
            PKG_MANAGER="apt"
            PKG_UPDATE="sudo apt-get update -qq"
            PKG_INSTALL="sudo apt-get install -y -qq"
            log "Distribución detectada: $DISTRO_ID (Debian-based, usando apt)"
            ;;
    esac
}

detect_distro

# Verificar si se ejecuta como root
if [ "$EUID" -ne 0 ]; then
    warn "Ejecutando con sudo..."
fi

# ==========================================
# 1. ACTUALIZAR SISTEMA
# ==========================================
echo ""
echo ">>> 1. Actualizando sistema..."
$PKG_UPDATE
if [ "$PKG_MANAGER" = "pacman" ]; then
    $PKG_INSTALL ca-certificates curl gnupg lsb-release
else
    $PKG_INSTALL ca-certificates curl gnupg lsb-release apt-transport-https software-properties-common
fi

# ==========================================
# 2. INSTALAR DOCKER
# ==========================================
echo ""
echo ">>> 2. Instalando Docker..."

if command -v docker &> /dev/null; then
    log "Docker ya está instalado: $(docker --version)"
else
    if [ "$PKG_MANAGER" = "pacman" ]; then
        # En Arch/Garuda, Docker está en los repos oficiales
        $PKG_INSTALL docker docker-compose docker-buildx
    else
        # Agregar clave GPG de Docker
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg

        # Agregar repositorio
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
          sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

        $PKG_UPDATE
        $PKG_INSTALL docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi

    # Habilitar e iniciar el servicio Docker
    sudo systemctl enable docker
    sudo systemctl start docker

    # Agregar usuario al grupo docker (evitar sudo)
    sudo usermod -aG docker $USER
    log "Docker instalado: $(docker --version)"
    warn "Cierra y abre la sesion para usar docker sin sudo, o ejecuta: newgrp docker"
fi

# ==========================================
# 3. INSTALAR KIND (Kubernetes in Docker)
# ==========================================
echo ""
echo ">>> 3. Instalando Kind..."

if command -v kind &> /dev/null; then
    log "Kind ya está instalado: $(kind version)"
else
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind
    log "Kind instalado: $(kind version)"
fi

# ==========================================
# 4. INSTALAR KUBECTL
# ==========================================
echo ""
echo ">>> 4. Instalando kubectl..."

if command -v kubectl &> /dev/null; then
    log "kubectl ya está instalado: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
else
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
    log "kubectl instalado: $(kubectl version --client)"
fi

# ==========================================
# 5. INSTALAR NODE.JS (NPM)
# ==========================================
echo ""
echo ">>> 5. Instalando Node.js..."

if command -v node &> /dev/null; then
    log "Node.js ya está instalado: $(node --version)"
else
    if [ "$PKG_MANAGER" = "pacman" ]; then
        # En Arch/Garuda, Node.js está en los repos oficiales
        $PKG_INSTALL nodejs npm
    else
        curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
        $PKG_INSTALL nodejs
    fi
    log "Node.js instalado: $(node --version)"
fi

# ==========================================
# 6. INSTALAR JENKINS
# ==========================================
echo ""
echo ">>> 6. Instalando Jenkins..."

if command -v jenkins &> /dev/null; then
    log "Jenkins ya está instalado"
else
    if [ "$PKG_MANAGER" = "pacman" ]; then
        # En Arch/Garuda, Jenkins está en los repos oficiales
        $PKG_INSTALL jenkins
    else
        curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
        echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
        $PKG_UPDATE
        $PKG_INSTALL jenkins
    fi

    # Habilitar e iniciar Jenkins
    sudo systemctl enable jenkins
    sudo systemctl start jenkins

    log "Jenkins instalado e iniciado"
    echo ""
    echo "  Para obtener la clave inicial de Jenkins:"
    echo "  sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
    echo ""
fi

# ==========================================
# 7. CREAR CLUSTER KIND
# ==========================================
echo ""
echo ">>> 7. Creando cluster Kind..."

if [ -n "$(kind get clusters 2>/dev/null)" ]; then
    log "Cluster Kind ya existe: $(kind get clusters | head -n1)"
else
    kind create cluster --name devops-lab --wait 120s
    log "Cluster Kind creado: devops-lab"
fi

CLUSTER_NAME=$(kind get clusters | head -n1)

# Verificar que kubectl funciona
kubectl cluster-info --context "kind-${CLUSTER_NAME}"

# ==========================================
# 7.5 INTEGRAR JENKINS CON DOCKER / KUBECTL / GIT
# ==========================================
echo ""
echo ">>> 7.5 Configurando el usuario jenkins..."

if id jenkins &> /dev/null; then
    # Jenkins necesita acceso a docker para construir imágenes
    sudo usermod -aG docker jenkins

    # Jenkins necesita el kubeconfig del cluster kind
    sudo mkdir -p /var/lib/jenkins/.kube
    kind get kubeconfig --name "${CLUSTER_NAME}" | sudo tee /var/lib/jenkins/.kube/config > /dev/null
    sudo chown -R jenkins:jenkins /var/lib/jenkins/.kube
    sudo chmod 600 /var/lib/jenkins/.kube/config

    # El home del usuario es 750: jenkins necesita permiso de transito (solo x,
    # no puede listar el contenido) para llegar al repo y clonarlo
    sudo setfacl -m u:jenkins:x "$HOME"

    # Git rechaza repos de otros usuarios ("dubious ownership") sin esto.
    # Se ejecuta desde / porque jenkins no puede hacer stat del directorio actual.
    sudo -u jenkins -H git -C / config --global --add safe.directory '*'

    # El plugin Git de Jenkins bloquea repos file:// por defecto (SECURITY-2478);
    # se habilita via propiedad de sistema en el servicio systemd
    sudo mkdir -p /etc/systemd/system/jenkins.service.d
    sudo tee /etc/systemd/system/jenkins.service.d/override.conf > /dev/null <<'EOF'
[Service]
Environment="JAVA_OPTS=-Djava.awt.headless=true -Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true"
EOF
    sudo systemctl daemon-reload
    sudo systemctl restart jenkins
    log "Usuario jenkins configurado (docker + kubeconfig + acceso al repo + git safe.directory)"
else
    warn "Usuario jenkins no existe todavía; reejecuta este paso despues de instalar Jenkins"
fi

# Guardar ruta del repositorio para que Jenkins la detecte automáticamente
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sudo mkdir -p /var/lib/jenkins
echo "$REPO_DIR" | sudo tee /var/lib/jenkins/repo-path > /dev/null
sudo chown jenkins:jenkins /var/lib/jenkins/repo-path
log "Ruta del repositorio guardada en /var/lib/jenkins/repo-path"

# ==========================================
# 8. INSTALAR GRAFANA Y PROMETHEUS
# ==========================================
echo ""
echo ">>> 8. Instalando Grafana y Prometheus..."

# Crear namespace de monitoreo
kubectl create namespace monitoring 2>/dev/null || true

# Instalar Prometheus con helm (si no está disponible, instalar helm primero)
if ! command -v helm &> /dev/null; then
    echo "Instalando Helm..."
    if [ "$PKG_MANAGER" = "pacman" ]; then
        $PKG_INSTALL helm
    else
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi
fi

# Agregar repositorios de Helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo update

# Instalar kube-prometheus-stack (incluye Prometheus + Grafana + AlertManager)
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --set grafana.adminPassword=admin \
    --set grafana.service.type=NodePort \
    --set grafana.service.nodePort=30080 \
    --set prometheus.service.type=NodePort \
    --set prometheus.service.nodePort=30090 \
    --set alertmanager.service.type=NodePort \
    --set alertmanager.service.nodePort=30093 \
    --wait --timeout 300s

log "Prometheus y Grafana instalados"

# ==========================================
# 9. VERIFICAR INSTALACION
# ==========================================
echo ""
echo "=========================================="
echo "  VERIFICACION DE INSTALACION"
echo "=========================================="

echo ""
echo "Herramientas instaladas:"
docker --version 2>/dev/null && log "Docker OK" || err "Docker NO instalado"
kind version 2>/dev/null && log "Kind OK" || err "Kind NO instalado"
kubectl version --client 2>/dev/null && log "kubectl OK" || err "kubectl NO instalado"
node --version 2>/dev/null && log "Node.js OK" || err "Node.js NO instalado"
npm --version 2>/dev/null && log "npm OK" || err "npm NO instalado"
helm version --short 2>/dev/null && log "Helm OK" || err "Helm NO instalado"

echo ""
echo "Cluster Kind:"
kind get clusters 2>/dev/null && log "Cluster OK" || warn "No hay clusters Kind"

echo ""
echo "Pods en namespace devops-lab:"
kubectl get pods -n devops-lab 2>/dev/null || warn "Namespace devops-lab no existe aún"

echo ""
echo "Pods de monitoreo:"
kubectl get pods -n monitoring 2>/dev/null || warn "Namespace monitoring no existe"

# ==========================================
# 10. PORT-FORWARDS DE MONITOREO
# ==========================================
echo ""
echo "=========================================="
echo "  INSTALACION COMPLETADA"
echo "=========================================="
echo ""
echo "Servicios disponibles:"
echo ""
echo "  Jenkins:        http://localhost:8090"
echo "  Frontend:       http://localhost:8081 (despues del pipeline)"
echo "  Backend API:    http://localhost:3000  (health: /health, version: /version, metricas: /metrics)"
echo "  Grafana:        http://localhost:3001 (admin/admin, con port-forward)"
echo "  Prometheus:     http://localhost:9090 (con port-forward)"
echo ""
echo "Para ejecutar los port-forwards de monitoreo:"
echo "  kubectl port-forward -n monitoring svc/prometheus-grafana 3001:80 &"
echo "  kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090 &"
echo ""
echo "Para ejecutar el pipeline desde Jenkins:"
echo "  1. Abre http://localhost:8080"
echo "  2. Obtén la clave inicial: sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
echo "  3. Configura Jenkins y ejecuta el pipeline"
echo ""
echo "Para ejecutar el pipeline manualmente:"
echo "  cd /home/rimuru129/Documents/DevOps\\ -\\ Proyecto\\ Kubernetes"
echo "  ./pipeline-build.sh"
echo ""
