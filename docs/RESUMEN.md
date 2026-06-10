# Resumen del proyecto — Cómo funciona todo

Documento de estudio para la defensa oral. Explica qué hace cada componente, cómo se conectan entre sí, y todas las configuraciones que hubo que hacer para que el pipeline funcione de punta a punta.

---

## 1. Visión general: ¿qué hace el sistema?

Es una plataforma DevOps completa para una aplicación **To-Do** (lista de tareas):

1. El código vive en un **repositorio Git** (rama `master`).
2. **Jenkins** ejecuta un pipeline que: clona el repo, instala dependencias, construye imágenes **Docker**, las publica (opcional) y despliega todo en **Kubernetes** con un botón (*Build Now* = despliegue manual obligatorio del examen).
3. La app corre en un cluster **kind** (Kubernetes dentro de Docker) con 3 pods: frontend (nginx), backend (Node.js) y base de datos (PostgreSQL).
4. **Prometheus** recolecta métricas del cluster y de la propia aplicación; **Grafana** las visualiza en dashboards.

```
Git (master) ──▶ Jenkins ──▶ Docker build ──▶ kind load ──▶ kubectl apply
                                                                │
                              ┌─────────────────────────────────┘
                              ▼
              namespace devops-lab:  frontend ─▶ backend ─▶ db
                                                    │ /metrics
              namespace monitoring:  Prometheus ◀───┘
                                         │
                                      Grafana
```

---

## 2. La aplicación

### Backend (`backend/`) — Node.js + Express, puerto 3000

- **CRUD de tareas** (`/tasks`): GET, POST, PUT, DELETE contra PostgreSQL.
- **`/health`**: devuelve estado de la app y de la conexión a la DB (`{status, db, uptime}`). Lo usan los *probes* de Kubernetes y el stage de Validación del pipeline.
- **`/version`**: devuelve `APP_NAME`, `APP_VERSION` y `APP_ENV`, **leídos de variables de entorno que vienen del ConfigMap** — demuestra el consumo de configuración externa.
- **`/metrics`**: métricas en formato Prometheus generadas con la librería `prom-client`: métricas estándar de Node.js (CPU, memoria, event loop) más dos métricas propias: `http_requests_total` (contador por método/ruta/status) y `http_request_duration_seconds` (histograma de latencias). Un middleware de Express las registra en cada request.
- **`/api-docs`**: documentación Swagger.
- **Credenciales**: `DB_USER` y `DB_PASSWORD` llegan por variables de entorno desde el **Secret** `postgres-secret` — la app nunca tiene contraseñas hardcodeadas.

### Frontend (`frontend/`) — HTML/JS servido por nginx, puerto 80

Página estática que consume la API del backend en `http://localhost:3000` (vía el port-forward). nginx solo sirve los archivos.

### Base de datos — PostgreSQL 16

- Usuario/contraseña/nombre de DB vienen del **Secret**.
- Un **ConfigMap** (`db-config.yml`) monta un `init.sql` en `/docker-entrypoint-initdb.d` que crea la tabla `tasks` al primer arranque.

---

## 3. Docker

Cada componente tiene su `Dockerfile`:

- **Backend**: parte de `node:18-alpine`, copia `package.json`, hace `npm install`, copia el código y ejecuta `node index.js`. Imagen: `todo-backend`.
- **Frontend**: parte de `nginx:alpine` y copia los archivos estáticos. Imagen: `todo-frontend`.

Como kind no puede descargar imágenes locales de un registry, el pipeline usa `kind load docker-image` para **inyectar las imágenes directamente en los nodos del cluster**, y los Deployments usan `imagePullPolicy: Never` (nunca intentes bajarla de internet, usá la local).

---

## 4. Kubernetes (cluster kind, namespace `devops-lab`)

| Objeto | Para qué sirve en este proyecto |
|---|---|
| **Namespace** `devops-lab` | Aísla todos los recursos de la app del resto del cluster |
| **Deployment** ×3 | Declaran el estado deseado (1 réplica de frontend, backend y db); Kubernetes recrea los pods si mueren |
| **Service** ×3 (ClusterIP) | DNS interno estable: el backend encuentra la DB como `db-service`, el frontend al backend como `backend-service` |
| **ConfigMap** `backend-config` | Configuración no sensible: `DB_HOST`, `DB_NAME`, `APP_NAME`, `APP_VERSION`, `APP_ENV` |
| **ConfigMap** `postgres-init` | El script SQL inicial de la DB |
| **Secret** `postgres-secret` | Credenciales de la DB (usuario/contraseña), inyectadas como variables de entorno |
| **ServiceMonitor** `backend-monitor` | Le dice a Prometheus que scrapee `/metrics` del backend cada 15 s |

Además los Deployments tienen:

- **livenessProbe** sobre `/health`: si la app deja de responder, Kubernetes reinicia el pod solo.
- **readinessProbe** sobre `/health`: el pod no recibe tráfico hasta estar listo.
- **resources (requests/limits)**: reserva de CPU/memoria. Son la base de los porcentajes que muestra Grafana (uso real vs. reservado).

---

## 5. Jenkins y el pipeline

### Cómo está montado

- Jenkins corre como **servicio systemd** en `http://localhost:8080`.
- Los jobs se crean ejecutando `jenkins/setup-jobs.groovy` en **Manage Jenkins → Script Console**. Crea 4 jobs:
  - **`deploy-full`**: el pipeline principal (archivo `Jenkinsfile` de la raíz).
  - **`deploy-monitoring`**: instala/actualiza Prometheus + Grafana con Helm, aplica el ServiceMonitor, levanta los port-forwards (Grafana 3001, Prometheus 9090) y valida que ambos respondan.
  - **`push-backend`** / **`push-frontend`**: publican las imágenes en Docker Hub.
- Los jobs son **"Pipeline from SCM"**: Jenkins clona el repo local (`file:///...`, rama `master`) y lee el Jenkinsfile desde ahí. Por eso **los cambios deben estar commiteados** para que Jenkins los vea.

### Etapas del pipeline `deploy-full` (mapeadas al examen)

| # | Stage | Qué hace |
|---|---|---|
| 1 | **Checkout** | Clona el repo Git y muestra el commit que va a desplegar |
| 2 | **Build** | `npm install` del backend; verifica que existan los archivos del frontend |
| 3 | **Docker Build** | `docker build` de las dos imágenes |
| 4 | **Push de Imagen** | (opcional, parámetro `PUSH_IMAGES`) login + push a Docker Hub con la credencial `dockerhub-credentials` guardada en Jenkins — nunca en el código |
| 5 | **Load Images into Kind** | Inyecta las imágenes en el cluster (detecta el nombre del cluster automáticamente) |
| 5 | **Deploy to Kubernetes** | `kubectl apply` de todos los manifests + `rollout restart` para que los pods tomen la imagen nueva |
| 7 | **Wait for Pods Ready** | Espera a que los 3 deployments estén Ready (timeout 120 s) |
| 7 | **Port-Forward** | Publica frontend en `localhost:8081` y backend en `localhost:3000` |
| 7 | **Validación** | `kubectl get pods` + `curl` a `/health`, `/version` y al frontend; si algo no responde, el pipeline falla |

**El despliegue es manual**: se dispara con el botón *Build Now* (requisito obligatorio). No hay trigger automático por commit.

---

## 6. Monitoreo: Prometheus + Grafana

### Cómo se instaló

Con **Helm** (el gestor de paquetes de Kubernetes), chart **kube-prometheus-stack**, en el namespace `monitoring`. Un solo comando instala Prometheus + Grafana + AlertManager + exporters + dashboards precargados (lo hace `install-all.sh`, paso 8).

### Cómo funciona Prometheus (puerto 9090)

- Modelo **pull**: cada 15-30 s va y "scrapea" endpoints HTTP `/metrics` de sus *targets*.
- Targets que ya trae el stack: los nodos (node-exporter → CPU/memoria/disco de la máquina), kubelet/cAdvisor (consumo por contenedor) y kube-state-metrics (estado de pods, deployments, réplicas).
- Target nuestro: el **backend**, descubierto mediante el `ServiceMonitor` `backend-monitor`. Requisito clave: el ServiceMonitor lleva el label `release: prometheus`, porque el operador solo adopta los que tienen el label de su release de Helm.
- Guarda todo como series de tiempo y se consulta con **PromQL**.

### Cómo funciona Grafana (puerto 3001 local, admin/admin)

- No recolecta nada: **consulta a Prometheus** (ya viene configurado como datasource) y dibuja dashboards.
- Dashboards listos: *Kubernetes / Compute Resources / Namespace (Pods)* → namespace `devops-lab` muestra CPU y memoria de cada pod **contra los requests/limits definidos en los manifests**.
- Métricas de la aplicación: en **Explore**, por ejemplo `rate(http_requests_total{app="todo-backend"}[1m])` muestra el tráfico HTTP real de la API.

### Accesos (port-forward)

```bash
kubectl port-forward -n monitoring svc/prometheus-grafana 3001:80 &
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090 &
```

---

## 7. Configuraciones que hubo que hacer para que el pipeline funcione

Esta sección es oro para la defensa: cada una fue un problema real con su solución.

| # | Configuración | Por qué hizo falta |
|---|---|---|
| 1 | **Rama `*/master` en los jobs** | Los jobs apuntaban a `*/main` pero el repo usa `master` → "no revision to build" |
| 2 | **`ALLOW_LOCAL_CHECKOUT=true`** como propiedad de Java en un *override* de systemd (`/etc/systemd/system/jenkins.service.d/override.conf`) | El plugin Git de Jenkins bloquea repos `file://` por seguridad (SECURITY-2478). Al ponerlo en systemd sobrevive a los reinicios |
| 3 | **`git config --global --add safe.directory '*'`** para el usuario `jenkins` | Git rechaza operar sobre repos de otro dueño ("dubious ownership"); el repo es de `rimuru129` y Jenkins corre como `jenkins` |
| 4 | **ACL de tránsito**: `setfacl -m u:jenkins:x /home/rimuru129` | El home del usuario es `750`: `jenkins` no podía ni atravesar el directorio para llegar al repo. Solo permiso `x` (pasar), no puede listar el contenido |
| 5 | **`usermod -aG docker jenkins`** | Sin estar en el grupo `docker`, Jenkins no puede construir imágenes (permiso denegado en el socket) |
| 6 | **Kubeconfig de kind copiado a `/var/lib/jenkins/.kube/config`** | El usuario `jenkins` necesita sus propias credenciales para usar `kubectl` contra el cluster |
| 7 | **Frontend en el puerto 8081** | El 8080 lo ocupa Jenkins; el port-forward del frontend al 8080 fallaba siempre por conflicto de puertos |
| 8 | **`kind load ... --name $(kind get clusters)`** | Sin `--name`, kind busca un cluster llamado `kind`; el nuestro se llama `devops-lab` |
| 9 | **`kubectl rollout restart` tras el apply** | Con `imagePullPolicy: Never` y el mismo tag de imagen, `kubectl apply` no detecta cambios y los pods seguirían corriendo la imagen vieja |
| 10 | **Label `release: prometheus` en el ServiceMonitor** | kube-prometheus-stack solo descubre ServiceMonitors etiquetados con su release de Helm; sin él, Prometheus ignoraba la app |
| 11 | **Credencial `dockerhub-credentials` en Jenkins** | El push a Docker Hub usa el almacén de credenciales de Jenkins (`withCredentials`); el token nunca aparece en el código ni en los logs |
| 12 | **`JENKINS_NODE_COOKIE=dontKillMe` en los port-forward** | Jenkins mata los procesos hijos al terminar el build; sin esto los port-forward morían al finalizar el pipeline |

Todo lo automatizable quedó en `install-all.sh` (pasos 7.5 en adelante), así la instalación es reproducible en una máquina limpia.

---

## 8. Flujo completo de una ejecución (para narrar en la demo)

1. Hago un cambio en el código y `git commit`.
2. En Jenkins aprieto **Build Now** en `deploy-full`.
3. Jenkins clona el repo, instala dependencias, construye las 2 imágenes Docker y las carga en kind.
4. Aplica los manifests: si algo cambió, Kubernetes hace rolling update; los probes garantizan que el tráfico solo llegue a pods sanos.
5. El stage de **Validación** comprueba pods Running y respuestas correctas de `/health`, `/version` y el frontend → el build queda verde.
6. Abro `http://localhost:8081` (app), Grafana (`:3001`) para ver CPU/memoria/pods, y Prometheus (`:9090` → Status → Targets) para mostrar que el backend está siendo scrapeado.
7. Genero carga (`for i in $(seq 1 500); do curl -s localhost:3000/tasks > /dev/null; done`) y muestro en Grafana cómo suben `http_requests_total` y el consumo de CPU.
