-- Core rsync operations for rsync.nvim
local M = {}

-- Dependencies
local Config = require("rsync.config")
local Pool = require("rsync.pool")
local Utils = require("rsync.utils")

-- Sync single file
function M.sync_file(file_path, direction, options, callback)
    -- Validate inputs
    if not file_path or file_path == "" then
        local error_msg = "File path is required"
        if callback then
            callback(false, error_msg)
        else
            return false, error_msg
        end
    end

    -- Check if file exists
    local stat = vim.loop.fs_stat(file_path)
    if not stat and direction == "upload" then
        local error_msg = "File does not exist: " .. file_path
        if callback then
            callback(false, error_msg)
        else
            return false, error_msg
        end
    end

    -- Check file size limits
    if not Config.is_file_size_allowed(file_path) then
        local error_msg = "File size exceeds limit: " .. file_path
        if callback then
            callback(false, error_msg)
        else
            return false, error_msg
        end
    end

    -- Determine if it's a directory
    local task_type = Pool.TASK_TYPE.FILE
    if stat and stat.isDirectory then
        task_type = Pool.TASK_TYPE.DIRECTORY
    end

    -- Add task to pool
    local task_id = Pool.add_task(task_type, file_path, direction, options, callback)

    if not callback then
        -- Synchronous mode: wait for completion
        return M.wait_for_task(task_id)
    end

    return task_id
end

-- Sync multiple files
function M.sync_files(file_paths, direction, options, callback)
    if not file_paths or #file_paths == 0 then
        local error_msg = "File paths are required"
        if callback then
            callback(false, error_msg)
        else
            return false, error_msg
        end
    end

    -- Filter and validate files
    local valid_files = {}
    for _, file_path in ipairs(file_paths) do
        if Config.is_file_size_allowed(file_path) then
            local stat = vim.loop.fs_stat(file_path)
            if stat then -- Only include existing files
                table.insert(valid_files, file_path)
            end
        end
    end

    if #valid_files == 0 then
        local error_msg = "No valid files to sync"
        if callback then
            callback(false, error_msg)
        else
            return false, error_msg
        end
    end

    -- Use batch processing for multiple files
    local batch_options = vim.deepcopy(options or {})
    batch_options.file_paths = valid_files

    local task_id = Pool.add_task(Pool.TASK_TYPE.BATCH, "", direction, batch_options, callback)

    if not callback then
        return M.wait_for_task(task_id)
    end

    return task_id
end

-- Sync directory
function M.sync_directory(dir_path, direction, options, callback)
    if not dir_path or dir_path == "" then
        local error_msg = "Directory path is required"
        if callback then
            callback(false, error_msg)
        else
            return false, error_msg
        end
    end

    -- Check if directory exists
    local stat = vim.loop.fs_stat(dir_path)
    if not stat and direction == "upload" then
        local error_msg = "Directory does not exist: " .. dir_path
        if callback then
            callback(false, error_msg)
        else
            return false, error_msg
        end
    end

    -- Add directory sync task
    local task_id = Pool.add_task(Pool.TASK_TYPE.DIRECTORY, dir_path, direction, options, callback)

    if not callback then
        return M.wait_for_task(task_id)
    end

    return task_id
end

-- Sync all (based on config)
function M.sync_all(callback)
    local local_path = Config.get("local_path")
    if not local_path or local_path == "" then
        local error_msg = "Local path not configured"
        if callback then
            callback(false, error_msg)
        else
            return false, error_msg
        end
    end

    -- Get all files in local path
    local all_files = Utils.scan_directory(local_path)

    -- Filter files based on patterns
    local filtered_files = Utils.filter_files(all_files)

    if #filtered_files == 0 then
        local msg = "No files to sync"
        if callback then
            callback(true, msg)
        else
            return true, msg
        end
    end

    return M.sync_files(filtered_files, "upload", {}, callback)
end

-- Wait for task completion (synchronous mode)
function M.wait_for_task(task_id, timeout)
    timeout = timeout or 300000 -- 5 minutes default
    local start_time = vim.loop.hrtime()

    while true do
        local status = Pool.get_status()
        local active_tasks = Pool.get_active_tasks()

        -- Check if task is completed
        local task_found = false
        for _, task in ipairs(active_tasks) do
            if task.id == task_id then
                task_found = true
                if task.status == Pool.TASK_STATUS.COMPLETED then
                    return true, task.result
                elseif task.status == Pool.TASK_STATUS.FAILED then
                    return false, task.result
                end
                break
            end
        end

        -- If task not found in active tasks, check if it was never queued or already completed
        if not task_found then
            return false, { message = "Task not found: " .. task_id }
        end

        -- Check timeout
        local elapsed = (vim.loop.hrtime() - start_time) / 1000000 -- Convert to milliseconds
        if elapsed > timeout then
            Pool.cancel_task(task_id)
            return false, { message = "Task timeout: " .. task_id }
        end

        -- Wait a bit before checking again
        vim.loop.sleep(100)
    end
end

-- Download file(s)
function M.download(paths, options, callback)
    if type(paths) == "string" then
        return M.sync_file(paths, "download", options, callback)
    elseif type(paths) == "table" then
        return M.sync_files(paths, "download", options, callback)
    else
        local error_msg = "Paths must be string or table"
        if callback then
            callback(false, error_msg)
        else
            return false, error_msg
        end
    end
end

-- Upload file(s)
function M.upload(paths, options, callback)
    if type(paths) == "string" then
        return M.sync_file(paths, "upload", options, callback)
    elseif type(paths) == "table" then
        return M.sync_files(paths, "upload", options, callback)
    else
        local error_msg = "Paths must be string or table"
        if callback then
            callback(false, error_msg)
        else
            return false, error_msg
        end
    end
end

-- Get sync status
function M.get_status()
    local pool_status = Pool.get_status()
    local active_tasks = Pool.get_active_tasks()

    local task_details = {}
    for _, task in ipairs(active_tasks) do
        table.insert(task_details, {
            id = task.id,
            type = task.type,
            path = task.path,
            direction = task.direction,
            status = task.status,
            created_at = task.created_at
        })
    end

    return {
        pool_status = pool_status,
        active_tasks = task_details
    }
end

-- Cancel sync operation
function M.cancel(task_id)
    return Pool.cancel_task(task_id)
end

-- Get file difference before sync
function M.get_file_diff(local_path, remote_path, callback)
    local Config = require("rsync.config")

    -- Build rsync dry-run command
    local cmd = {"rsync", "-n", "-a", "-i"}
    vim.list_extend(cmd, Config.get_rsync_options())
    vim.list_extend(cmd, {"-e", "ssh " .. table.concat(Config.get_ssh_options(), " ")})

    local source = local_path
    local destination = Config.get_remote_destination(remote_path or local_path)

    table.insert(cmd, source)
    table.insert(cmd, destination)

    local output = {}
    local errors = {}

    local handle = vim.fn.jobstart(cmd, {
        on_stdout = function(_, data)
            if data then
                vim.list_extend(output, data)
            end
        end,
        on_stderr = function(_, data)
            if data then
                vim.list_extend(errors, data)
            end
        end,
        on_exit = function(_, exit_code)
            if callback then
                -- Parse rsync output to determine changes
                local changes = {}
                for _, line in ipairs(output) do
                    if line and line ~= "" and not line:match("^total size is") then
                        table.insert(changes, line)
                    end
                end

                callback(exit_code == 0, {
                    changes = changes,
                    output = output,
                    errors = errors
                })
            end
        end
    })

    if handle <= 0 then
        if callback then
            callback(false, { message = "Failed to start rsync process" })
        end
        return false
    end

    return true
end

return M