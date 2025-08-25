# Task Tracker Demo Project - All 4 Layers

## **PROJECT OVERVIEW**

**Concept:** A simple task management system that demonstrates natural evolution from prototype to production.

**Core Features:**
- Create and list tasks
- Mark tasks as complete
- Filter tasks by status/priority
- Send notifications for overdue tasks

---

## **LAYER 1: LIVEBOOK PROTOTYPE**

### **File: `task_tracker_prototype.livemd`**

```markdown
# Task Tracker Prototype

## Data Structure Exploration

Let's start by defining our task structure and exploring the data:

```elixir
# Define our task structure
defmodule Task do
  defstruct [:id, :title, :description, :status, :priority, :due_date, :created_at]
end

# Sample data for exploration
tasks = [
  %Task{
    id: 1, 
    title: "Learn Livebook", 
    description: "Explore interactive development",
    status: :todo, 
    priority: :high, 
    due_date: ~D[2024-08-15],
    created_at: ~D[2024-08-01]
  },
  %Task{
    id: 2, 
    title: "Write CLI script", 
    description: "Create task management script",
    status: :in_progress, 
    priority: :medium,
    due_date: ~D[2024-08-20],
    created_at: ~D[2024-08-05]
  },
  %Task{
    id: 3, 
    title: "Build Elixir library", 
    description: "Structure as proper Mix project",
    status: :todo, 
    priority: :high,
    due_date: ~D[2024-08-25],
    created_at: ~D[2024-08-10]
  },
  %Task{
    id: 4, 
    title: "Create Phoenix app", 
    description: "Full web application with LiveView",
    status: :todo, 
    priority: :low,
    due_date: ~D[2024-09-01],
    created_at: ~D[2024-08-10]
  }
]
```

## Data Analysis

Let's explore our tasks and understand the patterns:

```elixir
# Group tasks by status
status_groups = Enum.group_by(tasks, & &1.status)
IO.inspect(status_groups, label: "Tasks by Status")

# Count tasks by priority
priority_counts = 
  tasks
  |> Enum.group_by(& &1.priority)
  |> Enum.map(fn {priority, task_list} -> {priority, length(task_list)} end)
  |> Enum.into(%{})

IO.inspect(priority_counts, label: "Priority Distribution")
```

```elixir
# Find high priority tasks
high_priority_tasks = 
  tasks
  |> Enum.filter(& &1.priority == :high)
  |> Enum.map(& &1.title)

IO.puts("High Priority Tasks:")
Enum.each(high_priority_tasks, &IO.puts("• #{&1}"))
```

```elixir
# Calculate completion percentage
total_tasks = length(tasks)
completed_tasks = tasks |> Enum.filter(& &1.status == :done) |> length()
in_progress_tasks = tasks |> Enum.filter(& &1.status == :in_progress) |> length()

completion_percentage = (completed_tasks / total_tasks) * 100
progress_percentage = ((completed_tasks + in_progress_tasks) / total_tasks) * 100

IO.puts("📊 Project Progress:")
IO.puts("  Completed: #{completed_tasks}/#{total_tasks} (#{completion_percentage}%)")
IO.puts("  In Progress: #{in_progress_tasks}/#{total_tasks}")
IO.puts("  Total Progress: #{progress_percentage}%")
```

## Task Operations

Let's define some basic operations:

```elixir
defmodule TaskOperations do
  def list_by_status(tasks, status) do
    Enum.filter(tasks, & &1.status == status)
  end
  
  def list_by_priority(tasks, priority) do
    Enum.filter(tasks, & &1.priority == priority)
  end
  
  def overdue_tasks(tasks, current_date \\ Date.utc_today()) do
    tasks
    |> Enum.filter(& &1.status != :done)
    |> Enum.filter(& Date.compare(&1.due_date, current_date) == :lt)
  end
  
  def mark_complete(tasks, task_id) do
    Enum.map(tasks, fn task ->
      if task.id == task_id do
        %{task | status: :done}
      else
        task
      end
    end)
  end
end

# Test our operations
todo_tasks = TaskOperations.list_by_status(tasks, :todo)
IO.inspect(todo_tasks, label: "TODO Tasks")

overdue = TaskOperations.overdue_tasks(tasks, ~D[2024-08-16])
IO.inspect(overdue, label: "Overdue Tasks")
```

## Visualization

```elixir
# Simple text-based visualization of task status
statuses = [:todo, :in_progress, :done]

Enum.each(statuses, fn status ->
  count = tasks |> Enum.filter(& &1.status == status) |> length()
  bar = String.duplicate("█", count)
  IO.puts("#{status |> Atom.to_string() |> String.upcase()}: #{bar} (#{count})")
end)
```

## Key Insights

From our exploration, we can see:
- Most tasks are still in TODO status
- High priority tasks need attention
- We need a way to track and notify about overdue tasks
- The basic operations are clear and simple

**Next Steps:** Transform this into a reusable CLI tool!
```

---

## **LAYER 2: CLI SCRIPT**

### **File: `task_tracker_cli.exs`**

```elixir
#!/usr/bin/env elixir

defmodule Task do
  @derive Jason.Encoder
  defstruct [:id, :title, :description, :status, :priority, :due_date, :created_at]
  
  def new(attrs) do
    %__MODULE__{
      id: System.unique_integer([:positive]),
      created_at: Date.utc_today(),
      status: :todo
    }
    |> Map.merge(Enum.into(attrs, %{}))
  end
end

defmodule TaskTracker.CLI do
  @tasks_file "tasks.json"

  def main(args) do
    case args do
      ["list"] -> list_tasks()
      ["list", "--status", status] -> list_tasks_by_status(status)
      ["list", "--priority", priority] -> list_tasks_by_priority(priority)
      ["add", title] -> add_task(title)
      ["add", title, priority] -> add_task(title, priority)
      ["complete", id] -> complete_task(String.to_integer(id))
      ["overdue"] -> list_overdue_tasks()
      ["stats"] -> show_stats()
      ["help"] -> show_help()
      [] -> show_help()
      _ -> 
        IO.puts("❌ Unknown command. Use 'help' to see available commands.")
        System.halt(1)
    end
  end

  defp load_tasks do
    case File.read(@tasks_file) do
      {:ok, content} ->
        content
        |> Jason.decode!()
        |> Enum.map(&struct(Task, atomize_keys(&1)))
      {:error, :enoent} -> []
      {:error, reason} ->
        IO.puts("❌ Error reading tasks: #{reason}")
        System.halt(1)
    end
  end

  defp save_tasks(tasks) do
    case Jason.encode(tasks, pretty: true) do
      {:ok, json} ->
        File.write!(@tasks_file, json)
      {:error, reason} ->
        IO.puts("❌ Error saving tasks: #{reason}")
        System.halt(1)
    end
  end

  defp atomize_keys(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
    |> Enum.into(%{})
  end

  defp list_tasks do
    tasks = load_tasks()
    if Enum.empty?(tasks) do
      IO.puts("📝 No tasks found. Add some with: task_tracker add 'Task title'")
    else
      IO.puts("📋 All Tasks:")
      print_tasks(tasks)
    end
  end

  defp list_tasks_by_status(status_str) do
    status = String.to_atom(status_str)
    tasks = load_tasks() |> Enum.filter(& &1.status == status)
    
    if Enum.empty?(tasks) do
      IO.puts("📝 No tasks with status '#{status_str}'")
    else
      IO.puts("📋 Tasks with status '#{status_str}':")
      print_tasks(tasks)
    end
  end

  defp list_tasks_by_priority(priority_str) do
    priority = String.to_atom(priority_str)
    tasks = load_tasks() |> Enum.filter(& &1.priority == priority)
    
    if Enum.empty?(tasks) do
      IO.puts("📝 No tasks with priority '#{priority_str}'")
    else
      IO.puts("📋 Tasks with priority '#{priority_str}':")
      print_tasks(tasks)
    end
  end

  defp add_task(title, priority_str \\ "medium") do
    priority = String.to_atom(priority_str)
    tasks = load_tasks()
    
    new_task = Task.new(%{
      title: title,
      priority: priority
    })
    
    updated_tasks = [new_task | tasks]
    save_tasks(updated_tasks)
    
    IO.puts("✅ Added task: #{title} (Priority: #{priority})")
  end

  defp complete_task(id) do
    tasks = load_tasks()
    
    case Enum.find(tasks, & &1.id == id) do
      nil ->
        IO.puts("❌ Task with ID #{id} not found")
        System.halt(1)
      task ->
        updated_tasks = 
          Enum.map(tasks, fn t ->
            if t.id == id do
              %{t | status: :done}
            else
              t
            end
          end)
        
        save_tasks(updated_tasks)
        IO.puts("✅ Completed task: #{task.title}")
    end
  end

  defp list_overdue_tasks do
    today = Date.utc_today()
    tasks = 
      load_tasks()
      |> Enum.filter(& &1.status != :done)
      |> Enum.filter(fn task ->
        case task.due_date do
          nil -> false
          due_date -> 
            due_date = Date.from_iso8601!(due_date)
            Date.compare(due_date, today) == :lt
        end
      end)
    
    if Enum.empty?(tasks) do
      IO.puts("🎉 No overdue tasks!")
    else
      IO.puts("⚠️  Overdue Tasks:")
      print_tasks(tasks)
    end
  end

  defp show_stats do
    tasks = load_tasks()
    total = length(tasks)
    
    if total == 0 do
      IO.puts("📊 No tasks to show stats for")
      return
    end
    
    by_status = Enum.group_by(tasks, & &1.status)
    by_priority = Enum.group_by(tasks, & &1.priority)
    
    completed = length(Map.get(by_status, :done, []))
    completion_rate = round((completed / total) * 100)
    
    IO.puts("📊 Task Statistics:")
    IO.puts("  Total tasks: #{total}")
    IO.puts("  Completion rate: #{completion_rate}%")
    IO.puts("")
    IO.puts("  By Status:")
    Enum.each([:todo, :in_progress, :done], fn status ->
      count = length(Map.get(by_status, status, []))
      percentage = round((count / total) * 100)
      IO.puts("    #{status}: #{count} (#{percentage}%)")
    end)
    
    IO.puts("")
    IO.puts("  By Priority:")
    Enum.each([:low, :medium, :high], fn priority ->
      count = length(Map.get(by_priority, priority, []))
      if count > 0 do
        percentage = round((count / total) * 100)
        IO.puts("    #{priority}: #{count} (#{percentage}%)")
      end
    end)
  end

  defp print_tasks(tasks) do
    Enum.each(tasks, fn task ->
      status_icon = case task.status do
        :todo -> "⭕"
        :in_progress -> "🔄"
        :done -> "✅"
      end
      
      priority_icon = case task.priority do
        :low -> "🔵"
        :medium -> "🟡"
        :high -> "🔴"
        _ -> "⚪"
      end
      
      due_info = case task.due_date do
        nil -> ""
        date -> " (Due: #{date})"
      end
      
      IO.puts("  #{status_icon} #{priority_icon} [#{task.id}] #{task.title}#{due_info}")
    end)
  end

  defp show_help do
    IO.puts("""
    📋 Task Tracker CLI
    
    Commands:
      list                          List all tasks
      list --status <status>        List tasks by status (todo|in_progress|done)
      list --priority <priority>    List tasks by priority (low|medium|high)
      add "<title>"                 Add a new task
      add "<title>" <priority>      Add a new task with priority
      complete <id>                 Mark task as complete
      overdue                       List overdue tasks
      stats                         Show task statistics
      help                          Show this help
      
    Examples:
      task_tracker add "Learn Elixir"
      task_tracker add "Build app" high
      task_tracker complete 1
      task_tracker list --status todo
    """)
  end
end

# Add Jason dependency check
try do
  Code.ensure_loaded!(Jason)
rescue
  UndefinedFunctionError ->
    IO.puts("❌ This script requires Jason for JSON handling.")
    IO.puts("Install with: mix archive.install hex jason")
    System.halt(1)
end

TaskTracker.CLI.main(System.argv())
```

### **Usage Examples:**
```bash
# Make executable
chmod +x task_tracker_cli.exs

# Add tasks
./task_tracker_cli.exs add "Learn Livebook"
./task_tracker_cli.exs add "Write CLI script" high

# List tasks
./task_tracker_cli.exs list
./task_tracker_cli.exs list --status todo

# Complete tasks
./task_tracker_cli.exs complete 1

# Show statistics
./task_tracker_cli.exs stats
```

---

## **LAYER 3: MIX LIBRARY**

### **Project Structure:**
```
task_tracker/
├── lib/
│   ├── task_tracker.ex
│   ├── task_tracker/
│   │   ├── application.ex
│   │   ├── repo.ex
│   │   ├── task.ex
│   │   ├── tasks.ex
│   │   └── workers/
│   │       └── notification_worker.ex
├── priv/
│   └── repo/
│       └── migrations/
├── test/
├── config/
└── mix.exs
```

### **File: `mix.exs`**
```elixir
defmodule TaskTracker.MixProject do
  use Mix.Project

  def project do
    [
      app: :task_tracker,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {TaskTracker.Application, []}
    ]
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.10"},
      {:postgrex, ">= 0.0.0"},
      {:oban, "~> 2.15"},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.29", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
```

### **File: `lib/task_tracker/application.ex`**
```elixir
defmodule TaskTracker.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TaskTracker.Repo,
      {Oban, Application.fetch_env!(:task_tracker, Oban)}
    ]

    opts = [strategy: :one_for_one, name: TaskTracker.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### **File: `lib/task_tracker/task.ex`**
```elixir
defmodule TaskTracker.Task do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tasks" do
    field :title, :string
    field :description, :string
    field :status, Ecto.Enum, values: [:todo, :in_progress, :done]
    field :priority, Ecto.Enum, values: [:low, :medium, :high]
    field :due_date, :date
    field :completed_at, :utc_datetime

    timestamps()
  end

  @doc false
  def changeset(task, attrs) do
    task
    |> cast(attrs, [:title, :description, :status, :priority, :due_date, :completed_at])
    |> validate_required([:title, :status, :priority])
    |> validate_length(:title, min: 1, max: 255)
    |> maybe_set_completed_at()
  end

  defp maybe_set_completed_at(%Ecto.Changeset{changes: %{status: :done}} = changeset) do
    put_change(changeset, :completed_at, DateTime.utc_now())
  end
  defp maybe_set_completed_at(changeset), do: changeset
end
```

### **File: `lib/task_tracker/tasks.ex`**
```elixir
defmodule TaskTracker.Tasks do
  @moduledoc """
  Context module for managing tasks.
  """

  import Ecto.Query, warn: false
  alias TaskTracker.Repo
  alias TaskTracker.Task
  alias TaskTracker.Workers.NotificationWorker

  @doc """
  Returns the list of tasks.
  """
  def list_tasks do
    Repo.all(Task)
  end

  @doc """
  Returns tasks filtered by status.
  """
  def list_tasks_by_status(status) do
    Task
    |> where([t], t.status == ^status)
    |> Repo.all()
  end

  @doc """
  Returns tasks filtered by priority.
  """
  def list_tasks_by_priority(priority) do
    Task
    |> where([t], t.priority == ^priority)
    |> Repo.all()
  end

  @doc """
  Returns overdue tasks (not completed and past due date).
  """
  def list_overdue_tasks(current_date \\ Date.utc_today()) do
    Task
    |> where([t], t.status != :done)
    |> where([t], t.due_date < ^current_date)
    |> Repo.all()
  end

  @doc """
  Gets a single task.
  """
  def get_task!(id), do: Repo.get!(Task, id)

  @doc """
  Creates a task.
  """
  def create_task(attrs \\ %{}) do
    %Task{}
    |> Task.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, task} = result ->
        schedule_reminder(task)
        result
      error -> error
    end
  end

  @doc """
  Updates a task.
  """
  def update_task(%Task{} = task, attrs) do
    changeset = Task.changeset(task, attrs)
    
    with {:ok, updated_task} <- Repo.update(changeset) do
      # Broadcast update for real-time features
      Phoenix.PubSub.broadcast(TaskTracker.PubSub, "tasks", {:task_updated, updated_task})
      {:ok, updated_task}
    end
  end

  @doc """
  Deletes a task.
  """
  def delete_task(%Task{} = task) do
    Repo.delete(task)
  end

  @doc """
  Returns task statistics.
  """
  def get_stats do
    total_query = from(t in Task, select: count(t.id))
    completed_query = from(t in Task, where: t.status == :done, select: count(t.id))
    
    total = Repo.one(total_query)
    completed = Repo.one(completed_query)
    
    completion_rate = if total > 0, do: Float.round(completed / total * 100, 1), else: 0
    
    %{
      total: total,
      completed: completed,
      completion_rate: completion_rate,
      by_status: get_count_by_status(),
      by_priority: get_count_by_priority()
    }
  end

  defp get_count_by_status do
    Task
    |> group_by([t], t.status)
    |> select([t], {t.status, count(t.id)})
    |> Repo.all()
    |> Enum.into(%{})
  end

  defp get_count_by_priority do
    Task
    |> group_by([t], t.priority)
    |> select([t], {t.priority, count(t.id)})
    |> Repo.all()
    |> Enum.into(%{})
  end

  @doc """
  Schedules a reminder notification for a task.
  """
  def schedule_reminder(%Task{due_date: nil}), do: :ok
  def schedule_reminder(%Task{due_date: due_date} = task) do
    reminder_date = Date.add(due_date, -1)
    
    if Date.compare(reminder_date, Date.utc_today()) == :gt do
      %{task_id: task.id, type: "reminder"}
      |> NotificationWorker.new(scheduled_at: DateTime.new!(reminder_date, ~T[09:00:00]))
      |> Oban.insert()
    end
    
    :ok
  end

  @doc """
  Subscribes to task updates for real-time features.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(TaskTracker.PubSub, "tasks")
  end
end
```

### **File: `lib/task_tracker/workers/notification_worker.ex`**
```elixir
defmodule TaskTracker.Workers.NotificationWorker do
  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias TaskTracker.Tasks

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"task_id" => task_id, "type" => type}}) do
    task = Tasks.get_task!(task_id)
    
    case type do
      "reminder" -> send_reminder(task)
      "overdue" -> send_overdue_alert(task)
      _ -> {:error, :unknown_notification_type}
    end
  end

  defp send_reminder(task) do
    # In a real app, this would send email, SMS, or push notification
    IO.puts("🔔 Reminder: Task '#{task.title}' is due tomorrow!")
    
    # Schedule overdue check for day after due date
    if task.due_date do
      overdue_date = Date.add(task.due_date, 1)
      
      %{task_id: task.id, type: "overdue"}
      |> __MODULE__.new(scheduled_at: DateTime.new!(overdue_date, ~T[10:00:00]))
      |> Oban.insert()
    end
    
    :ok
  end

  defp send_overdue_alert(task) do
    if task.status != :done do
      IO.puts("⚠️ Alert: Task '#{task.title}' is overdue!")
    end
    
    :ok
  end
end
```

### **File: `test/task_tracker/tasks_test.exs`**
```elixir
defmodule TaskTracker.TasksTest do
  use TaskTracker.DataCase
  alias TaskTracker.Tasks

  describe "tasks" do
    @valid_attrs %{
      title: "Test task",
      description: "A test task",
      status: :todo,
      priority: :medium
    }

    test "list_tasks/0 returns all tasks" do
      task = task_fixture()
      assert Tasks.list_tasks() == [task]
    end

    test "create_task/1 with valid data creates a task" do
      assert {:ok, task} = Tasks.create_task(@valid_attrs)
      assert task.title == "Test task"
      assert task.status == :todo
      assert task.priority == :medium
    end

    test "update_task/2 with valid data updates the task" do
      task = task_fixture()
      update_attrs = %{status: :done}

      assert {:ok, updated_task} = Tasks.update_task(task, update_attrs)
      assert updated_task.status == :done
      assert updated_task.completed_at != nil
    end

    test "list_overdue_tasks/1 returns only overdue tasks" do
      # Create task due yesterday
      yesterday = Date.add(Date.utc_today(), -1)
      overdue_task = task_fixture(%{due_date: yesterday})
      
      # Create task due tomorrow
      tomorrow = Date.add(Date.utc_today(), 1)
      _future_task = task_fixture(%{due_date: tomorrow})

      overdue_tasks = Tasks.list_overdue_tasks()
      assert length(overdue_tasks) == 1
      assert hd(overdue_tasks).id == overdue_task.id
    end
  end

  defp task_fixture(attrs \\ %{}) do
    {:ok, task} =
      attrs
      |> Enum.into(@valid_attrs)
      |> Tasks.create_task()

    task
  end
end
```

---

## **LAYER 4: PHOENIX APPLICATION**

### **File: `lib/task_tracker_web/live/task_live/index.ex`**
```elixir
defmodule TaskTrackerWeb.TaskLive.Index do
  use TaskTrackerWeb, :live_view

  alias TaskTracker.{Tasks, Task}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Tasks.subscribe()
    end

    {:ok,
     socket
     |> assign(:tasks, Tasks.list_tasks())
     |> assign(:stats, Tasks.get_stats())
     |> assign(:filter, :all)
     |> assign_form()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Tasks")
    |> assign(:task, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Task")
    |> assign(:task, %Task{})
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Task")
    |> assign(:task, Tasks.get_task!(id))
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    task = Tasks.get_task!(id)
    {:ok, _} = Tasks.delete_task(task)

    {:noreply, assign(socket, :tasks, Tasks.list_tasks())}
  end

  @impl true
  def handle_event("toggle_complete", %{"id" => id}, socket) do
    task = Tasks.get_task!(id)
    new_status = if task.status == :done, do: :todo, else: :done
    
    {:ok, _} = Tasks.update_task(task, %{status: new_status})

    {:noreply, 
     socket
     |> assign(:tasks, Tasks.list_tasks())
     |> assign(:stats, Tasks.get_stats())
    }
  end

  @impl true
  def handle_event("filter", %{"filter" => filter}, socket) do
    filter_atom = String.to_atom(filter)
    
    filtered_tasks = case filter_atom do
      :all -> Tasks.list_tasks()
      :overdue -> Tasks.list_overdue_tasks()
      status when status in [:todo, :in_progress, :done] -> 
        Tasks.list_tasks_by_status(status)
      priority when priority in [:low, :medium, :high] ->
        Tasks.list_tasks_by_priority(priority)
    end

    {:noreply,
     socket
     |> assign(:tasks, filtered_tasks)
     |> assign(:filter, filter_atom)
    }
  end

  @impl true
  def handle_info({:task_updated, _task}, socket) do
    {:noreply,
     socket
     |> assign(:tasks, Tasks.list_tasks())
     |> assign(:stats, Tasks.get_stats())
    }
  end

  defp assign_form(socket) do
    assign(socket, :form, to_form(%{}))
  end

  defp status_badge(status) do
    case status do
      :todo -> {"bg-gray-100 text-gray-800", "Todo"}
      :in_progress -> {"bg-blue-100 text-blue-800", "In Progress"}
      :done -> {"bg-green-100 text-green-800", "Done"}
    end
  end

  defp priority_badge(priority) do
    case priority do
      :low -> {"bg-green-100 text-green-800", "Low"}
      :medium -> {"bg-yellow-100 text-yellow-800", "Medium"}  
      :high -> {"bg-red-100 text-red-800", "High"}
    end
  end

  defp task_overdue?(%{due_date: nil}), do: false
  defp task_overdue?(%{due_date: due_date, status: :done}), do: false
  defp task_overdue?(%{due_date: due_date}) do
    Date.compare(due_date, Date.utc_today()) == :lt
  end
end
```

### **File: `lib/task_tracker_web/live/task_live/index.html.heex`**
```heex
<div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
  <div class="py-8">
    <!-- Header -->
    <div class="sm:flex sm:items-center sm:justify-between">
      <div>
        <h1 class="text-3xl font-bold text-gray-900">Task Tracker</h1>
        <p class="mt-2 text-sm text-gray-700">
          Manage your tasks efficiently with real-time updates
        </p>
      </div>
      <div class="mt-4 sm:mt-0">
        <.link
          patch={~p"/tasks/new"}
          class="inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
        >
          New Task
        </.link>
      </div>
    </div>

    <!-- Stats -->
    <div class="mt-8 grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4">
      <div class="bg-white overflow-hidden shadow rounded-lg">
        <div class="p-5">
          <div class="flex items-center">
            <div class="w-0 flex-1">
              <dl>
                <dt class="text-sm font-medium text-gray-500 truncate">Total Tasks</dt>
                <dd class="text-lg font-medium text-gray-900"><%= @stats.total %></dd>
              </dl>
            </div>
          </div>
        </div>
      </div>

      <div class="bg-white overflow-hidden shadow rounded-lg">
        <div class="p-5">
          <div class="flex items-center">
            <div class="w-0 flex-1">
              <dl>
                <dt class="text-sm font-medium text-gray-500 truncate">Completed</dt>
                <dd class="text-lg font-medium text-gray-900"><%= @stats.completed %></dd>
              </dl>
            </div>
          </div>
        </div>
      </div>

      <div class="bg-white overflow-hidden shadow rounded-lg">
        <div class="p-5">
          <div class="flex items-center">
            <div class="w-0 flex-1">
              <dl>
                <dt class="text-sm font-medium text-gray-500 truncate">Completion Rate</dt>
                <dd class="text-lg font-medium text-gray-900"><%= @stats.completion_rate %>%</dd>
              </dl>
            </div>
          </div>
        </div>
      </div>

      <div class="bg-white overflow-hidden shadow rounded-lg">
        <div class="p-5">
          <div class="flex items-center">
            <div class="w-0 flex-1">
              <dl>
                <dt class="text-sm font-medium text-gray-500 truncate">Overdue</dt>
                <dd class="text-lg font-medium text-red-600">
                  <%= @tasks |> Enum.count(&task_overdue?/1) %>
                </dd>
              </dl>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Filters -->
    <div class="mt-8 border-b border-gray-200">
      <nav class="-mb-px flex space-x-8">
        <button
          phx-click="filter"
          phx-value-filter="all"
          class={["py-2 px-1 border-b-2 font-medium text-sm",
            if(@filter == :all, do: "border-blue-500 text-blue-600", else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300")]}
        >
          All Tasks
        </button>
        
        <button
          phx-click="filter"
          phx-value-filter="todo"
          class={["py-2 px-1 border-b-2 font-medium text-sm",
            if(@filter == :todo, do: "border-blue-500 text-blue-600", else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300")]}
        >
          Todo
        </button>

        <button
          phx-click="filter"
          phx-value-filter="in_progress"
          class={["py-2 px-1 border-b-2 font-medium text-sm",
            if(@filter == :in_progress, do: "border-blue-500 text-blue-600", else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300")]}
        >
          In Progress
        </button>

        <button
          phx-click="filter"
          phx-value-filter="done"
          class={["py-2 px-1 border-b-2 font-medium text-sm",
            if(@filter == :done, do: "border-blue-500 text-blue-600", else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300")]}
        >
          Completed
        </button>

        <button
          phx-click="filter"
          phx-value-filter="overdue"
          class={["py-2 px-1 border-b-2 font-medium text-sm",
            if(@filter == :overdue, do: "border-red-500 text-red-600", else: "border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300")]}
        >
          Overdue
        </button>
      </nav>
    </div>

    <!-- Task List -->
    <div class="mt-8">
      <%= if Enum.empty?(@tasks) do %>
        <div class="text-center py-12">
          <h3 class="mt-2 text-sm font-medium text-gray-900">No tasks</h3>
          <p class="mt-1 text-sm text-gray-500">Get started by creating a new task.</p>
          <div class="mt-6">
            <.link
              patch={~p"/tasks/new"}
              class="inline-flex items-center px-4 py-2 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700"
            >
              New Task
            </.link>
          </div>
        </div>
      <% else %>
        <div class="bg-white shadow overflow-hidden sm:rounded-md">
          <ul role="list" class="divide-y divide-gray-200">
            <%= for task <- @tasks do %>
              <li class={["px-4 py-4 sm:px-6", if(task_overdue?(task), do: "bg-red-50", else: "")]}>
                <div class="flex items-center justify-between">
                  <div class="flex items-center">
                    <!-- Checkbox -->
                    <input
                      type="checkbox"
                      checked={task.status == :done}
                      phx-click="toggle_complete"
                      phx-value-id={task.id}
                      class="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300 rounded mr-4"
                    />
                    
                    <!-- Task Info -->
                    <div class="flex flex-col">
                      <div class="flex items-center space-x-2">
                        <p class={["text-sm font-medium", if(task.status == :done, do: "text-gray-500 line-through", else: "text-gray-900")]}>
                          <%= task.title %>
                        </p>
                        
                        <!-- Status Badge -->
                        <% {badge_class, badge_text} = status_badge(task.status) %>
                        <span class={["inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium", badge_class]}>
                          <%= badge_text %>
                        </span>
                        
                        <!-- Priority Badge -->
                        <% {priority_class, priority_text} = priority_badge(task.priority) %>
                        <span class={["inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium", priority_class]}>
                          <%= priority_text %>
                        </span>

                        <!-- Overdue Warning -->
                        <%= if task_overdue?(task) do %>
                          <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800">
                            Overdue
                          </span>
                        <% end %>
                      </div>
                      
                      <%= if task.description do %>
                        <p class="mt-1 text-sm text-gray-500"><%= task.description %></p>
                      <% end %>
                      
                      <%= if task.due_date do %>
                        <p class="mt-1 text-sm text-gray-500">Due: <%= Calendar.strftime(task.due_date, "%B %d, %Y") %></p>
                      <% end %>
                    </div>
                  </div>
                  
                  <!-- Actions -->
                  <div class="flex items-center space-x-2">
                    <.link
                      patch={~p"/tasks/#{task.id}/edit"}
                      class="text-blue-600 hover:text-blue-900 text-sm font-medium"
                    >
                      Edit
                    </.link>
                    
                    <button
                      phx-click="delete"
                      phx-value-id={task.id}
                      data-confirm="Are you sure?"
                      class="text-red-600 hover:text-red-900 text-sm font-medium"
                    >
                      Delete
                    </button>
                  </div>
                </div>
              </li>
            <% end %>
          </ul>
        </div>
      <% end %>
    </div>
  </div>
</div>

<!-- Modal -->
<.modal :if={@live_action in [:new, :edit]} id="task-modal" show on_cancel={JS.patch(~p"/tasks")}>
  <.live_component
    module={TaskTrackerWeb.TaskLive.FormComponent}
    id={@task.id || :new}
    title={@page_title}
    action={@live_action}
    task={@task}
    patch={~p"/tasks"}
  />
</.modal>
```

---

## **DEMO FLOW SUMMARY**

### **Presentation Flow:**
1. **Layer 1 (Livebook):** Show interactive data exploration, live results
2. **Layer 2 (Script):** Transform Livebook logic into CLI tool  
3. **Layer 3 (Library):** Add proper structure, database, background jobs
4. **Layer 4 (Phoenix):** Full web app with real-time features

### **Key Demonstrations:**
- Same core task management logic across all layers
- Natural evolution from simple to complex
- Each layer builds on the previous one
- Real-time updates in Phoenix showing the power of LiveView
- Background job processing with Oban

### **Audience Takeaways:**
- How to start simple and evolve naturally
- When to use each tooling layer
- The power of Elixir's coherent ecosystem
- Practical patterns they can apply immediately

This demo project provides a concrete, relatable example that audiences can understand and replicate in their own work.