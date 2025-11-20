-- Connection pool and batch processing for rsync.nvim
local M = {}

-- Pool state
local pool = {
    connections = {},
    active_jobs = {},
    pending_tasks = {},
    status = {
        total_connections = 0,
        active_connections = 0,
        pending_tasks = 0,
        completed_tasks = 0,
        failed_tasks = 0
    }
}

-- Configuration
local config = require("rsync.config")

-- Task types
local TASK_TYPE = {
    FILE = "file",
    DIRECTORY = "directory",
    BATCH = "batch"
}

-- Task status
local TASK_STATUS = {
    PENDING = "pending",
    RUNNING = "running",
    COMPLETED = "completed",
    FAILED = "failed"
}

-- Create a unique task ID
local function generate_task_id()
    return string.format("%d_%d", os.time(), math.random(1000, 9999))
end

-- Batch files by size and type for optimal processing
local function batch_files(file_paths, batch_size)
    local batches = {}
    local current_batch = {}
    local current_size = 0

    for _, file_path in ipairs(file_paths) do
        local stat = vim.loop.fs_stat(file_path)
        if stat and not stat.isDirectory then
            if #current_batch >= batch_size or current_size > 50 * 1024 * 1024 then -- 50MB per batch
                if #current_batch > 0 then
                    table.insert(batches, current_batch)
                    current_batch = {}
                    current_size = 0
                end
            end
            table.insert(current_batch, file_path)
            current_size = current_size + (stat.size or 0)
        end
    end

    if #current_batch > 0 then
        table.insert(batches, current_batch)
    end

    return batches
end

-- Execute rsync command asynchronously
local function execute_rsync_command(source, destination, options, callback)
    local Config = require("rsync.config")

    -- Build rsync command
    local cmd = {"rsync"}
    vim.list_extend(cmd, Config.get_rsync_options())
    vim.list_extend(cmd, options)
    vim.list_extend(cmd, {"-e", "ssh " .. table.concat(Config.get_ssh_options(), " ")})
    table.insert(cmd, source)
    table.insert(cmd, destination)

    local cmd_str = table.concat(cmd, " ")
    vim.notify("Executing: " .. cmd_str, vim.log.levels.DEBUG)

    local handle = vim.fn.jobstart(cmd, {
        on_stdout = function(_, data)
            if data and #data > 0 then
                for _, line in ipairs(data) do
                    if line and line ~= "" then
                        vim.notify("rsync: " .. line, vim.log.levels.DEBUG)
                    end
                end
            end
        end,
        on_stderr = function(_, data)
            if data and #data > 0 then
                for _, line in ipairs(data) do
                    if line and line ~= "" then
                        vim.notify("rsync error: " .. line, vim.log.levels.WARN)
                    end
                end
            end
        end,
        on_exit = function(_, exit_code)
            if exit_code == 0 then
                callback(true, "Success")
            else
                callback(false, "Exit code: " .. exit_code)
            end
        end
    })

    if handle <= 0 then
        callback(false, "Failed to start rsync process")
        return nil
    end

    return handle
end

-- Process a single task
local function process_task(task)
    task.status = TASK_STATUS.RUNNING
    pool.status.active_connections = pool.status.active_connections + 1

    local callback = function(success, message)
        task.status = success and TASK_STATUS.COMPLETED or TASK_STATUS.FAILED
        task.result = { success = success, message = message }

        pool.status.active_connections = pool.status.active_connections - 1
        if success then
            pool.status.completed_tasks = pool.status.completed_tasks + 1
        else
            pool.status.failed_tasks = pool.status.failed_tasks + 1
        end

        -- Call task completion callback
        if task.callback then
            task.callback(success, message, task)
        end

        -- Process next pending task
        M.process_next_task()
    end

    local source, destination

    if task.direction == "upload" then
        source = task.path
        destination = config.get_remote_destination(task.remote_path or task.path)
    else -- download
        source = config.get_remote_destination(task.remote_path or task.path)
        destination = task.path
    end

    local options = {}
    if task.type == TASK_TYPE.DIRECTORY then
        table.insert(options, "-r") -- recursive
    end

    task.handle = execute_rsync_command(source, destination, options, callback)

    if not task.handle then
        callback(false, "Failed to execute rsync command")
    end
end

-- Process batch task
local function process_batch_task(task)
    task.status = TASK_STATUS.RUNNING
    pool.status.active_connections = pool.status.active_connections + 1

    local batches = batch_files(task.file_paths, config.get("batch_size", 50))
    local completed_batches = 0
    local total_batches = #batches
    local batch_results = {}

    local function process_next_batch()
        if completed_batches >= total_batches then
            -- All batches completed
            local all_success = true
            for _, result in ipairs(batch_results) do
                if not result.success then
                    all_success = false
                    break
                end
            end

            task.status = all_success and TASK_STATUS.COMPLETED or TASK_STATUS.FAILED
            task.result = {
                success = all_success,
                message = all_success and "All batches completed" or "Some batches failed",
                batch_results = batch_results
            }

            pool.status.active_connections = pool.status.active_connections - 1
            if all_success then
                pool.status.completed_tasks = pool.status.completed_tasks + 1
            else
                pool.status.failed_tasks = pool.status.failed_tasks + 1
            end

            if task.callback then
                task.callback(all_success, task.result.message, task)
            end

            M.process_next_task()
            return
        end

        completed_batches = completed_batches + 1
        local current_batch = batches[completed_batches]

        -- Create temporary file list for this batch
        local temp_file = vim.fn.tempname()
        local file_list = table.concat(current_batch, "\n")
        vim.fn.writefile(vim.split(file_list, "\n"), temp_file)

        local source = "--files-from=" .. temp_file
        local destination

        if task.direction == "upload" then
            destination = config.get_remote_destination(task.remote_path or ".")
        else
            source = config.get_remote_destination(task.remote_path or ".") .. " " .. source
            destination = "."
        end

        local options = {"--from-file", "--relative"}

        local callback = function(success, message)
            -- Clean up temp file
            vim.fn.delete(temp_file)

            table.insert(batch_results, {
                batch_num = completed_batches,
                success = success,
                message = message,
                file_count = #current_batch
            })

            if success then
                vim.notify(string.format("Batch %d/%d completed (%d files)",
                    completed_batches, total_batches, #current_batch), vim.log.levels.INFO)
            else
                vim.notify(string.format("Batch %d/%d failed: %s",
                    completed_batches, total_batches, message), vim.log.levels.ERROR)
            end

            -- Schedule next batch (small delay to prevent overwhelming)
            vim.defer_fn(process_next_batch, 100)
        end

        task.current_batch_handle = execute_rsync_command(source, destination, options, callback)
    end

    process_next_batch()
end

-- Add task to pending queue
function M.add_task(task_type, path, direction, options, callback)
    local task = {
        id = generate_task_id(),
        type = task_type,
        path = path,
        direction = direction, -- "upload" or "download"
        remote_path = options and options.remote_path,
        callback = callback,
        status = TASK_STATUS.PENDING,
        created_at = os.time(),
        result = nil
    }

    if task_type == TASK_TYPE.BATCH then
        task.file_paths = options and options.file_paths or {}
    end

    table.insert(pool.pending_tasks, task)
    pool.status.pending_tasks = pool.status.pending_tasks + 1

    -- Try to process immediately if resources available
    M.process_next_task()

    return task.id
end

-- Process next pending task
function M.process_next_task()
    local max_connections = config.get("max_connections", 5)

    if pool.status.active_connections >= max_connections then
        return false
    end

    if #pool.pending_tasks == 0 then
        return false
    end

    -- Get next pending task
    local task = table.remove(pool.pending_tasks, 1)
    pool.status.pending_tasks = pool.status.pending_tasks - 1

    table.insert(pool.active_jobs, task)

    -- Process based on task type
    if task.type == TASK_TYPE.BATCH then
        process_batch_task(task)
    else
        process_task(task)
    end

    return true
end

-- Initialize pool
function M.setup()
    -- Reset pool state
    pool.connections = {}
    pool.active_jobs = {}
    pool.pending_tasks = {}
    pool.status = {
        total_connections = 0,
        active_connections = 0,
        pending_tasks = 0,
        completed_tasks = 0,
        failed_tasks = 0
    }

    vim.notify("Rsync connection pool initialized", vim.log.levels.INFO)
end

-- Get pool status
function M.get_status()
    return vim.deepcopy(pool.status)
end

-- Get active tasks
function M.get_active_tasks()
    return vim.deepcopy(pool.active_jobs)
end

-- Cancel task
function M.cancel_task(task_id)
    -- Check active jobs
    for i, task in ipairs(pool.active_jobs) do
        if task.id == task_id then
            if task.handle and task.handle > 0 then
                vim.fn.jobstop(task.handle)
            end
            if task.current_batch_handle and task.current_batch_handle > 0 then
                vim.fn.jobstop(task.current_batch_handle)
            end

            table.remove(pool.active_jobs, i)
            pool.status.active_connections = math.max(0, pool.status.active_connections - 1)

            task.status = TASK_STATUS.FAILED
            task.result = { success = false, message = "Task cancelled" }

            if task.callback then
                task.callback(false, "Task cancelled", task)
            end

            return true
        end
    end

    -- Check pending tasks
    for i, task in ipairs(pool.pending_tasks) do
        if task.id == task_id then
            table.remove(pool.pending_tasks, i)
            pool.status.pending_tasks = math.max(0, pool.status.pending_tasks - 1)
            return true
        end
    end

    return false
end

-- Cleanup pool
function M.cleanup()
    -- Cancel all active jobs
    for _, task in ipairs(pool.active_jobs) do
        if task.handle and task.handle > 0 then
            vim.fn.jobstop(task.handle)
        end
        if task.current_batch_handle and task.current_batch_handle > 0 then
            vim.fn.jobstop(task.current_batch_handle)
        end
    end

    -- Clear all tasks
    pool.active_jobs = {}
    pool.pending_tasks = {}
    pool.status.active_connections = 0
    pool.status.pending_tasks = 0

    vim.notify("Rsync connection pool cleaned up", vim.log.levels.INFO)
end

-- Export task types
M.TASK_TYPE = TASK_TYPE
M.TASK_STATUS = TASK_STATUS

return M