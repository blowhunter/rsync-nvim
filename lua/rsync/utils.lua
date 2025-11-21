-- Utility functions for rsync-nvim
local M = {}

-- Dependencies
local Config = require("rsync.config")

-- Escape shell arguments
function M.escape_shell_arg(arg)
    return "'" .. arg:gsub("'", "'\"'\"'") .. "'"
end

-- Normalize path separators
function M.normalize_path(path)
    return path:gsub("\\", "/"):gsub("/+$", "")
end

-- Get relative path from base directory
function M.get_relative_path(full_path, base_path)
    full_path = M.normalize_path(full_path)
    base_path = M.normalize_path(base_path)

    if full_path:sub(1, #base_path) == base_path then
        return full_path:sub(#base_path + 2)
    end
    return full_path
end

-- Check if path matches any pattern
function M.matches_patterns(path, patterns)
    if not patterns or #patterns == 0 then
        return false
    end

    for _, pattern in ipairs(patterns) do
        if path:match(pattern) then
            return true
        end
    end

    return false
end

-- Scan directory recursively
function M.scan_directory(dir_path, include_dirs)
    local files = {}
    local dirs = include_dirs and {} or nil

    local function scan_recursive(current_path)
        local handle = vim.loop.fs_scandir(current_path)
        if not handle then return end

        while true do
            local name, type = vim.loop.fs_scandir_next(handle)
            if not name then break end

            local full_path = current_path .. "/" .. name

            if type == "directory" then
                if include_dirs then
                    table.insert(dirs, M.get_relative_path(full_path, dir_path))
                end
                scan_recursive(full_path)
            elseif type == "file" then
                table.insert(files, full_path)
            end
        end
    end

    scan_recursive(dir_path)

    if include_dirs then
        return files, dirs
    end
    return files
end

-- Filter files based on include/exclude patterns
function M.filter_files(file_paths)
    local include_patterns = Config.get("include_patterns", {})
    local exclude_patterns = Config.get("exclude_patterns", {})

    local filtered_files = {}
    local local_path = Config.get("local_path")

    for _, file_path in ipairs(file_paths) do
        -- Get relative path for pattern matching
        local relative_path = M.get_relative_path(file_path, local_path)

        -- Check exclude patterns first
        if not M.matches_patterns(relative_path, exclude_patterns) then
            -- If include patterns are specified, check them
            if #include_patterns == 0 or M.matches_patterns(relative_path, include_patterns) then
                table.insert(filtered_files, file_path)
            end
        end
    end

    return filtered_files
end

-- Format file size for human reading
function M.format_file_size(bytes)
    if not bytes or bytes == 0 then return "0 B" end

    local units = {"B", "KB", "MB", "GB", "TB"}
    local size = bytes
    local unit_index = 1

    while size >= 1024 and unit_index < #units do
        size = size / 1024
        unit_index = unit_index + 1
    end

    return string.format("%.1f %s", size, units[unit_index])
end

-- Get file modification time
function M.get_file_mtime(file_path)
    local stat = vim.loop.fs_stat(file_path)
    if stat then
        return stat.mtime.sec
    end
    return nil
end

-- Validate SSH connection
function M.validate_ssh_connection(callback)
    local Config = require("rsync.config")

    local host = Config.get("host")
    local username = Config.get("username")

    -- Validate required parameters
    if not host or host == "" then
        if callback then
            callback(false, "Host is not configured", {})
        end
        return false
    end

    if not username or username == "" then
        if callback then
            callback(false, "Username is not configured", {})
        end
        return false
    end

    -- Build SSH test command with proper error handling
    local cmd = {"ssh"}

    -- Safely extend with SSH options
    local ssh_options = Config.get_ssh_options()
    if ssh_options and type(ssh_options) == "table" then
        vim.list_extend(cmd, ssh_options)
    end

    -- Add connection test options
    vim.list_extend(cmd, {
        "-o", "BatchMode=yes",  -- No password prompts
        "-o", "ConnectTimeout=10",
        "-o", "LogLevel=ERROR"  -- Reduce verbose output
    })

    -- Add target and test command
    table.insert(cmd, username .. "@" .. host)
    table.insert(cmd, "echo 'Connection successful'")

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
                local success = exit_code == 0
                local message = success and "SSH connection successful" or
                               ("SSH connection failed: " .. table.concat(errors, " "))
                callback(success, message, {
                    output = output,
                    errors = errors,
                    exit_code = exit_code
                })
            end
        end
    })

    if handle <= 0 then
        if callback then
            local cmd_str = table.concat(cmd, " ")
            callback(false, "Failed to start SSH test process: " .. cmd_str, {
                cmd = cmd_str,
                handle = handle
            })
        end
        return false
    end

    return true
end

-- Convert glob pattern to Lua pattern
function M.glob_to_pattern(glob_pattern)
    local lua_pattern = glob_pattern
        :gsub("%.", "%%.")
        :gsub("%*", ".+")
        :gsub("%?", ".")
        :gsub("%[", "%%[")
        :gsub("%]", "%%]")
    return "^" .. lua_pattern .. "$"
end

-- Safe file operations with retry
function M.safe_file_operation(operation, max_retries)
    max_retries = max_retries or 3

    for attempt = 1, max_retries do
        local success, result = pcall(operation)

        if success then
            return true, result
        elseif attempt < max_retries then
            vim.loop.sleep(100 * attempt) -- Incremental delay
        end
    end

    return false, "Operation failed after " .. max_retries .. " attempts"
end

return M