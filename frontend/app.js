const API = "http://localhost:3000";

async function loadTasks() {
    const res = await fetch(`${API}/tasks`);
    const data = await res.json();

    const list = document.getElementById("list");
    list.innerHTML = "";

    data.forEach(task => {
        const li = document.createElement("li");

        li.innerHTML = `
        ${task.title}
        <div class="actions">
            <button class="edit-btn" onclick="editTask(${task.id}, '${task.title}')">Editar</button>
            <button class="delete-btn" onclick="deleteTask(${task.id})">Borrar</button>
        </div>
        `;

        list.appendChild(li);
    });
}

async function addTask() {
    const input = document.getElementById("taskInput");

    await fetch(`${API}/tasks`, {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({ title: input.value })
    });

    input.value = "";
    loadTasks();
}

async function deleteTask(id) {
    await fetch(`${API}/tasks/${id}`, { method: "DELETE" });
    loadTasks();
}

async function editTask(id, oldTitle) {
    const newTitle = prompt("Editar tarea:", oldTitle);

    await fetch(`${API}/tasks/${id}`, {
        method: "PUT",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({ title: newTitle })
    });

    loadTasks();
}

loadTasks();
