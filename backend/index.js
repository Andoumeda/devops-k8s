const express = require("express");
const { Pool } = require("pg");
const cors = require("cors");
const swaggerUi = require("swagger-ui-express");

const app = express();
app.use(cors());
app.use(express.json());

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

app.listen(3000, () => console.log("Backend corriendo en 3000"));
