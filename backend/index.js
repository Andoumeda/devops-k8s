const express = require("express");
const { Pool } = require("pg");
const cors = require("cors");
const swaggerUi = require("swagger-ui-express");
const promClient = require("prom-client");
const pkg = require("./package.json");

const APP_NAME = process.env.APP_NAME || pkg.name;
const APP_VERSION = process.env.APP_VERSION || pkg.version;
const APP_ENV = process.env.APP_ENV || "development";

const app = express();
app.use(cors());
app.use(express.json());

/* Métricas Prometheus */
const register = new promClient.Registry();
register.setDefaultLabels({ app: APP_NAME });
promClient.collectDefaultMetrics({ register });

const httpRequestsTotal = new promClient.Counter({
    name: "http_requests_total",
    help: "Cantidad total de requests HTTP",
    labelNames: ["method", "route", "status"],
    registers: [register],
});

const httpRequestDuration = new promClient.Histogram({
    name: "http_request_duration_seconds",
    help: "Duración de los requests HTTP en segundos",
    labelNames: ["method", "route", "status"],
    registers: [register],
});

app.use((req, res, next) => {
    const end = httpRequestDuration.startTimer();
    res.on("finish", () => {
        const route = req.route ? req.baseUrl + req.route.path : req.path;
        httpRequestsTotal.inc({ method: req.method, route, status: res.statusCode });
        end({ method: req.method, route, status: res.statusCode });
    });
    next();
});

const pool = new Pool({
    host: process.env.DB_HOST,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
});

// Swagger config
const swaggerDocument = {
    openapi: "3.0.0",
    info: {
        title: "ToDo API",
        version: "1.0.0",
        description: "API CRUD simple para gestión de tareas",
    },
    servers: [
        {
            url: "http://localhost:3000",
        },
    ],
    components: {
        schemas: {
            Task: {
                type: "object",
                properties: {
                    id: {
                        type: "integer",
                        example: 1,
                    },
                    title: {
                        type: "string",
                        example: "Comprar pan",
                    },
                },
            },
            TaskInput: {
                type: "object",
                properties: {
                    title: {
                        type: "string",
                        example: "Nueva tarea",
                    },
                },
                required: ["title"],
            },
        },
    },
    paths: {
        "/health": {
            get: {
                summary: "Estado de salud de la aplicación y la base de datos",
                responses: {
                    200: {
                        description: "Estado de la aplicación",
                        content: {
                            "application/json": {
                                example: { status: "ok", db: "up", uptime: 123.4 },
                            },
                        },
                    },
                },
            },
        },
        "/version": {
            get: {
                summary: "Versión de la aplicación (desde ConfigMap)",
                responses: {
                    200: {
                        description: "Información de versión",
                        content: {
                            "application/json": {
                                example: { app: "todo-backend", version: "1.0.0", environment: "kubernetes" },
                            },
                        },
                    },
                },
            },
        },
        "/tasks": {
            get: {
                summary: "Obtener todas las tareas",
                responses: {
                    200: {
                        description: "Lista de tareas",
                        content: {
                            "application/json": {
                                schema: {
                                    type: "array",
                                    items: { $ref: "#/components/schemas/Task" },
                                },
                            },
                        },
                    },
                },
            },
            post: {
                summary: "Crear una nueva tarea",
                requestBody: {
                    required: true,
                    content: {
                        "application/json": {
                            schema: { $ref: "#/components/schemas/TaskInput" },
                        },
                    },
                },
                responses: {
                    200: {
                        description: "Tarea creada",
                        content: {
                            "application/json": {
                                schema: { $ref: "#/components/schemas/Task" },
                            },
                        },
                    },
                },
            },
        },

        "/tasks/{id}": {
            put: {
                summary: "Actualizar una tarea",
                parameters: [
                    {
                        name: "id",
                        in: "path",
                        required: true,
                        schema: {
                            type: "integer",
                        },
                        description: "ID de la tarea",
                    },
                ],
                requestBody: {
                    required: true,
                    content: {
                        "application/json": {
                            schema: { $ref: "#/components/schemas/TaskInput" },
                        },
                    },
                },
                responses: {
                    200: {
                        description: "Tarea actualizada",
                        content: {
                            "application/json": {
                                schema: { $ref: "#/components/schemas/Task" },
                            },
                        },
                    },
                },
            },

            delete: {
                summary: "Eliminar una tarea",
                parameters: [
                    {
                        name: "id",
                        in: "path",
                        required: true,
                        schema: {
                            type: "integer",
                        },
                        description: "ID de la tarea",
                    },
                ],
                responses: {
                    200: {
                        description: "Tarea eliminada",
                        content: {
                            "application/json": {
                                example: { success: true },
                            },
                        },
                    },
                },
            },
        },
    },
};

app.use("/api-docs", swaggerUi.serve, swaggerUi.setup(swaggerDocument));

/* Salud, versión y métricas */

// GET /health - usado por los probes de Kubernetes y la validación del pipeline
app.get("/health", async (req, res) => {
    let db = "up";
    try {
        await pool.query("SELECT 1");
    } catch (err) {
        db = "down";
    }
    res.json({
        status: "ok",
        db,
        uptime: process.uptime(),
        timestamp: new Date().toISOString(),
    });
});

// GET /version - APP_NAME/APP_VERSION/APP_ENV vienen del ConfigMap backend-config
app.get("/version", (req, res) => {
    res.json({
        app: APP_NAME,
        version: APP_VERSION,
        environment: APP_ENV,
        node: process.version,
    });
});

// GET /metrics - scrapeado por Prometheus (ServiceMonitor backend-monitor)
app.get("/metrics", async (req, res) => {
    res.set("Content-Type", register.contentType);
    res.end(await register.metrics());
});

/* CRUD */

// GET
app.get("/tasks", async (req, res) => {
    const result = await pool.query("SELECT * FROM tasks ORDER BY id");
    res.json(result.rows);
});

// POST
app.post("/tasks", async (req, res) => {
    const { title } = req.body;
    const result = await pool.query(
        "INSERT INTO tasks (title) VALUES ($1) RETURNING *",
                                    [title]
    );
    res.json(result.rows[0]);
});

// PUT
app.put("/tasks/:id", async (req, res) => {
    const { id } = req.params;
    const { title } = req.body;

    const result = await pool.query(
        "UPDATE tasks SET title=$1 WHERE id=$2 RETURNING *",
        [title, id]
    );

    res.json(result.rows[0]);
});

// DELETE
app.delete("/tasks/:id", async (req, res) => {
    const { id } = req.params;
    await pool.query("DELETE FROM tasks WHERE id=$1", [id]);
    res.json({ success: true });
});

app.listen(3000, () =>
    console.log(`${APP_NAME} v${APP_VERSION} (${APP_ENV}) corriendo en 3000`)
);
