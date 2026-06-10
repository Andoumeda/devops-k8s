# Examen Final DevOps — Plataforma CI/CD con Jenkins, Kubernetes y Monitoreo

Solución DevOps completa para la empresa ficticia **"Nimbus Software S.A."**: aplicación To-Do (frontend web + backend API REST + PostgreSQL) construida, desplegada y monitoreada de forma automatizada con Jenkins, Docker, Kubernetes (kind), Prometheus y Grafana.

---

## 1. Arquitectura

```
                         ┌──────────────────────────────────────────────────┐
                         │                 Cluster kind (K8s)               │
 ┌─────────┐   build     │  namespace: devops-lab                           │
 │   Git   │──────────┐  │  ┌──────────┐   ┌──────────┐   ┌──────────────┐  │
 │ (repo)  │          │  │  │ frontend │──▶│ backend  │──▶│ db (postgres)│  │
 └─────────┘          ▼  │  │  nginx   │   │ node.js  │   │  + Secret    │  │
 ┌─────────┐   ┌────────┐│  │  :80     │   │  :3000   │   │  + ConfigMap │  │
 │ Jenkins │──▶│ Docker ││  └──────────┘   └─────┬────┘   └──────────────┘  │
 │  :8080  │   │ images ││                       │ /metrics                 │
 └─────────┘   └────────┘│  namespace: monitoring│                          │
      │ kubectl apply    │  ┌────────────┐  ┌────▼─────────┐                │
      └─────────────────▶│  │  Grafana   │◀─│  Prometheus  │                │
                         │  │  :3001     │  │  :9090       │                │
                         │  └────────────┘  └──────────────┘                │
                         └──────────────────────────────────────────────────┘
```

**Componentes:**

| Componente | Tecnología | Función |
|---|---|---|
| Frontend | HTML/JS + nginx | Interfaz web de tareas (To-Do) |
| Backend | Node.js + Express | API REST CRUD + `/health` + `/version` + `/metrics` |
| Base de datos | PostgreSQL 16 | Persistencia de tareas |
| CI/CD | Jenkins | Pipeline de build, push y deploy manual (Build Now) |
| Contenedores | Docker | Imágenes `todo-backend` y `todo-frontend` |
| Orquestación | Kubernetes (kind) | Namespace, Deployments, Services, ConfigMaps, Secret |
| Monitoreo | Prometheus + Grafana | Métricas de pods, CPU, memoria y de la aplicación |

**Objetos Kubernetes utilizados** (`manifests/`):

| Objeto | Archivo(s) |
|---|---|
| Namespace `devops-lab` | `namespace.yml` |
| Deployments (frontend, backend, db) | `front-deploy.yml`, `back-deploy.yml`, `db-deploy.yml` |
| Services (ClusterIP) | `front-svc.yml`, `back-svc.yml`, `db-svc.yml` |
| ConfigMaps | `back-config.yml` (DB_HOST, APP_VERSION…), `db-config.yml` (init.sql) |
| Secret | `db-secret.yml` (usuario/contraseña de PostgreSQL) |
| ServiceMonitor | `back-servicemonitor.yml` (scrape de `/metrics` del backend) |

El backend consume su configuración por **variables de entorno**: las no sensibles vienen del ConfigMap `backend-config` (`DB_HOST`, `DB_NAME`, `APP_NAME`, `APP_VERSION`, `APP_ENV`) y las credenciales del **Secret** `postgres-secret` (`DB_USER`, `DB_PASSWORD`).

---

## 2. Estructura del repositorio

```
├── backend/                  # API REST Node.js + Dockerfile
├── frontend/                 # Web estática servida por nginx + Dockerfile
├── manifests/                # YAML de Kubernetes
├── jenkins/
│   ├── setup-jobs.groovy     # Crea los jobs en Jenkins (Script Console)
│   ├── Jenkinsfile.push-backend
│   └── Jenkinsfile.push-frontend
├── Jenkinsfile               # Pipeline principal (deploy-full)
├── install-all.sh            # Instalador de todo el entorno
└── docs/evidencias/          # Capturas para la defensa
```

---

## 3. Instalación

### 3.1 Requisitos
Ubuntu/Debian con `sudo`. Todo lo demás lo instala el script.

### 3.2 Instalación automática

```bash
./install-all.sh
```

El script instala y configura: Docker, kind, kubectl, Node.js, Jenkins, Helm, crea el cluster kind, configura el usuario `jenkins` (grupo docker, kubeconfig, git `safe.directory`) e instala **kube-prometheus-stack** (Prometheus + Grafana + AlertManager) en el namespace `monitoring`.

### 3.3 Configurar Jenkins (una sola vez)

1. Abrir `http://localhost:8080` y desbloquear con:
   ```bash
   sudo cat /var/lib/jenkins/secrets/initialAdminPassword
   ```
2. Instalar los plugins sugeridos (incluyen Git y Pipeline).
3. Ir a **Manage Jenkins → Script Console**, pegar el contenido de `jenkins/setup-jobs.groovy` y ejecutar. Esto crea:
   - `deploy-full` — pipeline completo (checkout → build → docker → deploy → validación)
   - `push-backend` / `push-frontend` — publicación de imágenes en Docker Hub
4. (Solo para push) Completar usuario y token en **Manage Jenkins → Credentials → Global → dockerhub-credentials**.

> Los jobs usan *Pipeline from SCM* sobre el repo local (rama `master`): los cambios deben estar **commiteados** para que Jenkins los vea.

---

## 4. Pipeline CI/CD

El pipeline `deploy-full` (archivo `Jenkinsfile`) implementa las etapas obligatorias del examen:

| Etapa del examen | Stage en el Jenkinsfile | Qué hace |
|---|---|---|
| 1. Checkout | `Checkout` | Clona el repo Git (rama master) |
| 2. Build | `Build` | `npm install` del backend + verificación del frontend |
| 3. Docker Build | `Docker Build` | Construye `todo-backend` y `todo-frontend` |
| 4. Push de imagen | `Push de Imagen` | Sube las imágenes a Docker Hub (parámetro `PUSH_IMAGES`; también disponible como jobs separados `push-backend`/`push-frontend`) |
| 5. Deploy en K8s | `Load Images into Kind` + `Deploy to Kubernetes` | Carga imágenes en kind y aplica todos los manifests |
| 7. Validación | `Wait for Pods Ready` + `Validación` | Espera pods Ready, verifica `kubectl get pods`, `curl /health`, `curl /version` y frontend accesible |

**El despliegue es manual y se dispara con el botón "Build Now"** del job `deploy-full` en Jenkins (requisito obligatorio del examen). No hay trigger automático por commit.

### Ejecución

1. Abrir `http://localhost:8080` → job **deploy-full** → **Build Now**.
2. Al terminar, quedan disponibles:

| URL | Servicio |
|---|---|
| `http://localhost:8081` | Frontend (To-Do) |
| `http://localhost:3000/tasks` | API REST |
| `http://localhost:3000/health` | Health check (estado app + DB) |
| `http://localhost:3000/version` | Versión (leída del ConfigMap) |
| `http://localhost:3000/metrics` | Métricas Prometheus de la app |
| `http://localhost:3000/api-docs` | Swagger UI |

> El frontend usa el puerto **8081** porque el 8080 lo ocupa Jenkins.

---

## 5. Monitoreo

### 5.1 Acceso

```bash
kubectl port-forward -n monitoring svc/prometheus-grafana 3001:80 &
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090 &
```

- **Grafana**: `http://localhost:3001` (usuario `admin`, contraseña `admin`)
- **Prometheus**: `http://localhost:9090`

### 5.2 Qué se monitorea

- **Pods / CPU / memoria**: kube-prometheus-stack trae dashboards listos en Grafana. Ver **Dashboards → Kubernetes / Compute Resources / Namespace (Pods)** y filtrar por namespace `devops-lab`.
- **Aplicación**: el backend expone `/metrics` con `prom-client` (métricas default de Node.js + `http_requests_total` + `http_request_duration_seconds`). El `ServiceMonitor` `backend-monitor` hace que Prometheus lo scrapee cada 15 s.

### 5.3 Consultas PromQL útiles para la defensa

```promql
# Estado de los pods del namespace
kube_pod_status_phase{namespace="devops-lab"}

# CPU por pod
rate(container_cpu_usage_seconds_total{namespace="devops-lab"}[5m])

# Memoria por pod
container_memory_working_set_bytes{namespace="devops-lab"}

# Requests HTTP de la aplicación (por ruta y código)
rate(http_requests_total{app="todo-backend"}[1m])

# Latencia p95 de la API
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
```

Para generar tráfico y ver las métricas moverse durante la demo:

```bash
for i in $(seq 1 100); do curl -s http://localhost:3000/tasks > /dev/null; done
```

---

## 6. Evidencias

Las capturas para la defensa se guardan en `docs/evidencias/`:

- Pipeline `deploy-full` verde en Jenkins (vista de stages)
- `kubectl get all -n devops-lab` con todos los pods Running
- Respuesta de `/health` y `/version`
- Frontend funcionando en `http://localhost:8081`
- Target del backend en Prometheus (**Status → Targets**, job `backend-monitor` UP)
- Dashboard de Grafana con CPU/memoria del namespace `devops-lab`
- Gráfica de `http_requests_total` durante una prueba de carga

---

## 7. Problemas encontrados y soluciones

| Problema | Causa | Solución |
|---|---|---|
| Los jobs de Jenkins no encontraban revisión para construir | Los jobs apuntaban a la rama `*/main` pero el repo usa `master` | Se corrigió `setup-jobs.groovy` para usar `*/master` |
| El script de Script Console fallaba con `MissingPropertyException` | Se intentó definir los pipelines como strings inline *dollar-slashy*; Groovy interpolaba `${...}` al ejecutar el setup | Se volvió a *Pipeline from SCM*: los jobs leen los Jenkinsfile directamente del repo |
| El port-forward del frontend fallaba siempre | Conflicto de puertos: Jenkins y el frontend usaban ambos el 8080 | El frontend se publica en el **8081** |
| `kind load docker-image` no encontraba el cluster | Sin `--name`, kind asume un cluster llamado `kind`, pero el nuestro se llama `devops-lab` | El pipeline detecta el nombre con `kind get clusters` y pasa `--name` |
| Jenkins no podía clonar el repo local | Git bloquea repos de otros usuarios (*dubious ownership*) | `sudo -u jenkins git config --global --add safe.directory '*'` (lo hace `install-all.sh`) |
| Jenkins no podía usar Docker ni kubectl | El usuario `jenkins` no estaba en el grupo `docker` y no tenía kubeconfig | `install-all.sh` lo agrega al grupo y copia el kubeconfig de kind a `/var/lib/jenkins/.kube/config` |
| Los pods no tomaban la imagen nueva tras un re-deploy | Con `imagePullPolicy: Never` y el mismo tag, `kubectl apply` no reinicia nada | El pipeline ejecuta `kubectl rollout restart` tras aplicar los manifests |
| Prometheus no scrapeaba la app | El stack solo descubre ServiceMonitors con el label del release | Se agregó `release: prometheus` al `ServiceMonitor` |

---

## 8. Comandos útiles

```bash
# Estado del cluster
kubectl get all -n devops-lab
kubectl get all -n monitoring

# Logs
kubectl logs -n devops-lab deploy/backend -f

# Probar endpoints
curl http://localhost:3000/health
curl http://localhost:3000/version
curl http://localhost:3000/metrics | head -30

# Reiniciar un deployment
kubectl rollout restart deployment/backend -n devops-lab

# Borrar todo y volver a empezar
kubectl delete namespace devops-lab
```
