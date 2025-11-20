-- Neovim commands for rsync-nvim
local M = {}

-- Dependencies
local Core = require("rsync.core")
local Config = require("rsync.config")
local Pool = require("rsync.pool")
local Utils = require("rsync.utils")

-- Register all commands
function M.register()
    -- File sync commands
    vim.api.nvim_create_user_command("RsyncUpload", function(opts)
        M.handle_upload_command(opts)
    end, {
        nargs = "?",
        complete = "file",
        desc = "Upload file(s) to remote server"
    })

    vim.api.nvim_create_user_command("RsyncDownload", function(opts)
        M.handle_download_command(opts)
    end, {
        nargs = "?",
        complete = "file",
        desc = "Download file(s) from remote server"
    })

    -- Directory sync commands
    vim.api.nvim_create_user_command("RsyncUploadDir", function(opts)
        M.handle_upload_dir_command(opts)
    end, {
        nargs = "?",
        complete = "dir",
        desc = "Upload directory to remote server"
    })

    vim.api.nvim_create_user_command("RsyncDownloadDir", function(opts)
        M.handle_download_dir_command(opts)
    end, {
        nargs = "?",
        complete = "dir",
        desc = "Download directory from remote server"
    })

    -- Project sync commands
    vim.api.nvim_create_user_command("RsyncSync", function(opts)
        M.handle_sync_command(opts)
    end, {
        nargs = 0,
        desc = "Sync entire project"
    })

    vim.api.nvim_create_user_command("RsyncSyncBuffer", function(opts)
        M.handle_sync_buffer_command(opts)
    end, {
        nargs = 0,
        desc = "Sync current buffer"
    })

    -- Status commands
    vim.api.nvim_create_user_command("RsyncStatus", function(opts)
        M.handle_status_command(opts)
    end, {
        nargs = 0,
        desc = "Show rsync operation status"
    })

    -- Configuration commands
    vim.api.nvim_create_user_command("RsyncConfig", function(opts)
        M.handle_config_command(opts)
    end, {
        nargs = "?",
        complete = "customlist,v:lua.RsyncConfigComplete",
        desc = "Show or set rsync configuration"
    })

    vim.api.nvim_create_user_command("RsyncTestConnection", function(opts)
        M.handle_test_connection_command(opts)
    end, {
        nargs = 0,
        desc = "Test SSH connection to remote server"
    })

    -- Diff commands
    vim.api.nvim_create_user_command("RsyncDiff", function(opts)
        M.handle_diff_command(opts)
    end, {
        nargs = "?",
        complete = "file",
        desc = "Show differences between local and remote files"
    })

    -- Cancel commands
    vim.api.nvim_create_user_command("RsyncCancel", function(opts)
        M.handle_cancel_command(opts)
    end, {
        nargs = "?",
        desc = "Cancel rsync operation"
    })

    -- Configuration setup command
    vim.api.nvim_create_user_command("RsyncSetup", function(opts)
        M.handle_setup_command(opts)
    end, {
        nargs = 0,
        desc = "Interactive configuration setup for rsync-nvim"
    })

    -- Setup completion for config command
    vim.fn.RsyncConfigComplete = function(ArgLead, CmdLine, CursorPos)
        local config_keys = {
            "host", "username", "port", "private_key_path",
            "local_path", "remote_path", "auto_sync", "sync_on_save",
            "sync_interval", "max_connections", "batch_size", "config_file_reminder"
        }

        local matches = {}
        for _, key in ipairs(config_keys) do
            if key:find("^" .. ArgLead) then
                table.insert(matches, key)
            end
        end

        return matches
    end
end

-- Handle upload command
function M.handle_upload_command(opts)
    -- Verify configuration before proceeding
    if not Config.is_configured() then
        vim.notify("Cannot upload: rsync is not configured. Please create a .rsync.json file or run :RsyncSetup", vim.log.levels.ERROR)
        return
    end

    local args = opts.fargs

    if #args == 0 then
        -- Upload current buffer file
        local buf_file = vim.api.nvim_buf_get_name(0)
        if buf_file == "" then
            vim.notify("No file to upload", vim.log.levels.ERROR)
            return
        end

        M.upload_with_feedback({buf_file})
    else
        -- Upload specified files
        local files = {}
        for _, arg in ipairs(args) do
            local expanded = vim.fn.glob(arg, false, true)
            vim.list_extend(files, expanded)
        end

        if #files == 0 then
            vim.notify("No files found matching: " .. table.concat(args, " "), vim.log.levels.ERROR)
            return
        end

        M.upload_with_feedback(files)
    end
end

-- Handle download command
function M.handle_download_command(opts)
    -- Verify configuration before proceeding
    if not Config.is_configured() then
        vim.notify("Cannot download: rsync is not configured. Please create a .rsync.json file or run :RsyncSetup", vim.log.levels.ERROR)
        return
    end

    local args = opts.fargs

    if #args == 0 then
        vim.notify("Please specify file(s) to download", vim.log.levels.ERROR)
        return
    end

    M.download_with_feedback(args)
end

-- Handle upload directory command
function M.handle_upload_dir_command(opts)
    -- Verify configuration before proceeding
    if not Config.is_configured() then
        vim.notify("Cannot upload directory: rsync is not configured. Please create a .rsync.json file or run :RsyncSetup", vim.log.levels.ERROR)
        return
    end

    local dir_path = opts.args

    if dir_path == "" or dir_path == nil then
        -- Use current buffer's directory
        local buf_file = vim.api.nvim_buf_get_name(0)
        if buf_file == "" then
            vim.notify("No directory to upload", vim.log.levels.ERROR)
            return
        end
        dir_path = vim.fn.fnamemodify(buf_file, ":h")
    end

    local stat = vim.loop.fs_stat(dir_path)
    if not stat then
        vim.notify("Directory does not exist: " .. dir_path, vim.log.levels.ERROR)
        return
    end

    if not stat.isDirectory then
        vim.notify("Not a directory: " .. dir_path, vim.log.levels.ERROR)
        return
    end

    Core.sync_directory(dir_path, "upload", {}, function(success, message)
        if success then
            vim.notify("Directory uploaded successfully: " .. dir_path, vim.log.levels.INFO)
        else
            vim.notify("Failed to upload directory: " .. (message or "Unknown error"), vim.log.levels.ERROR)
        end
    end)
end

-- Handle download directory command
function M.handle_download_dir_command(opts)
    -- Verify configuration before proceeding
    if not Config.is_configured() then
        vim.notify("Cannot download directory: rsync is not configured. Please create a .rsync.json file or run :RsyncSetup", vim.log.levels.ERROR)
        return
    end

    local dir_path = opts.args

    if dir_path == "" or dir_path == nil then
        vim.notify("Please specify directory to download", vim.log.levels.ERROR)
        return
    end

    Core.sync_directory(dir_path, "download", {}, function(success, message)
        if success then
            vim.notify("Directory downloaded successfully: " .. dir_path, vim.log.levels.INFO)
        else
            vim.notify("Failed to download directory: " .. (message or "Unknown error"), vim.log.levels.ERROR)
        end
    end)
end

-- Handle sync command
function M.handle_sync_command(opts)
    -- Verify configuration before proceeding
    if not Config.is_configured() then
        vim.notify("Cannot sync project: rsync is not configured. Please create a .rsync.json file or run :RsyncSetup", vim.log.levels.ERROR)
        return
    end

    Core.sync_all(function(success, message)
        if success then
            vim.notify("Project sync completed", vim.log.levels.INFO)
        else
            vim.notify("Project sync failed: " .. (message or "Unknown error"), vim.log.levels.ERROR)
        end
    end)
end

-- Handle sync buffer command
function M.handle_sync_buffer_command(opts)
    -- Verify configuration before proceeding
    if not Config.is_configured() then
        vim.notify("Cannot sync buffer: rsync is not configured. Please create a .rsync.json file or run :RsyncSetup", vim.log.levels.ERROR)
        return
    end

    local buf_file = vim.api.nvim_buf_get_name(0)
    if buf_file == "" then
        vim.notify("No file to sync", vim.log.levels.ERROR)
        return
    end

    Core.sync_file(buf_file, "upload", {}, function(success, message)
        if success then
            vim.notify("Buffer synced successfully", vim.log.levels.INFO)
        else
            vim.notify("Buffer sync failed: " .. (message or "Unknown error"), vim.log.levels.ERROR)
        end
    end)
end

-- Handle status command
function M.handle_status_command(opts)
    local status = Core.get_status()
    local pool_status = status.pool_status
    local active_tasks = status.active_tasks

    -- Create status buffer
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})

    local lines = {}

    -- Header
    table.insert(lines, "=== Rsync Status ===")
    table.insert(lines, "")

    -- Pool status
    table.insert(lines, "Pool Status:")
    table.insert(lines, string.format("  Active Connections: %d/%d", pool_status.active_connections, Config.get("max_connections", 5)))
    table.insert(lines, string.format("  Pending Tasks: %d", pool_status.pending_tasks))
    table.insert(lines, string.format("  Completed Tasks: %d", pool_status.completed_tasks))
    table.insert(lines, string.format("  Failed Tasks: %d", pool_status.failed_tasks))
    table.insert(lines, "")

    -- Active tasks
    if #active_tasks > 0 then
        table.insert(lines, "Active Tasks:")
        for _, task in ipairs(active_tasks) do
            local status_icon = task.status == "running" and "🔄" or "⏳"
            local direction_icon = task.direction == "upload" and "↑" or "↓"
            table.insert(lines, string.format("  %s [%s] %s %s", status_icon, task.id:sub(1, 8), direction_icon, task.path))
        end
        table.insert(lines, "")
    else
        table.insert(lines, "No active tasks")
        table.insert(lines, "")
    end

    -- Configuration info
    table.insert(lines, "Configuration:")
    table.insert(lines, string.format("  Host: %s@%s:%d", Config.get("username"), Config.get("host"), Config.get("port")))
    table.insert(lines, string.format("  Local Path: %s", Config.get("local_path")))
    table.insert(lines, string.format("  Remote Path: %s", Config.get("remote_path")))
    table.insert(lines, string.format("  Auto Sync: %s", Config.get("auto_sync") and "Enabled" or "Disabled"))
    table.insert(lines, string.format("  Sync on Save: %s", Config.get("sync_on_save") and "Enabled" or "Disabled"))

    -- Set buffer content
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    -- Buffer settings
    vim.api.nvim_buf_set_option(buf, "modifiable", false)
    vim.api.nvim_buf_set_option(buf, "filetype", "text")

    -- Open in window
    vim.cmd("split")
    vim.api.nvim_win_set_buf(0, buf)
    vim.api.nvim_buf_set_name(buf, "Rsync Status")

    -- Set up keymaps to close
    vim.api.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>", { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", ":close<CR>", { noremap = true, silent = true })
end

-- Handle config command
function M.handle_config_command(opts)
    local args = opts.fargs

    if #args == 0 then
        -- Show current configuration
        local config = Config.get()
        local config_lines = {"=== Rsync Configuration ==="}

        -- Function to sort config keys
        local function sort_config(t)
            local keys = {}
            for k in pairs(t) do
                table.insert(keys, k)
            end
            table.sort(keys)
            return keys
        end

        for _, key in ipairs(sort_config(config)) do
            local value = config[key]
            local value_str = tostring(value)

            if type(value) == "table" then
                value_str = vim.inspect(value)
            elseif type(value) == "boolean" then
                value_str = value and "true" or "false"
            end

            table.insert(config_lines, string.format("%s = %s", key, value_str))
        end

        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, config_lines)
        vim.api.nvim_buf_set_option(buf, "modifiable", false)

        vim.cmd("split")
        vim.api.nvim_win_set_buf(0, buf)
        vim.api.nvim_buf_set_name(buf, "Rsync Config")

        vim.api.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>", { noremap = true, silent = true })
    else
        -- Set configuration value
        local key = args[1]
        local value = args[2]

        if not value then
            vim.notify("Usage: RsyncConfig <key> <value>", vim.log.levels.ERROR)
            return
        end

        -- Try to parse as JSON for complex values
        if value:find("{") or value:find("%[") then
            local ok, parsed = pcall(vim.json.decode, value)
            if ok then
                Config.set(key, parsed)
            else
                Config.set(key, value)
            end
        else
            -- Try to parse as boolean or number
            if value == "true" then
                Config.set(key, true)
            elseif value == "false" then
                Config.set(key, false)
            elseif tonumber(value) then
                Config.set(key, tonumber(value))
            else
                Config.set(key, value)
            end
        end

        vim.notify(string.format("Set %s = %s", key, value), vim.log.levels.INFO)
    end
end

-- Handle test connection command
function M.handle_test_connection_command(opts)
    -- Verify configuration before proceeding
    if not Config.is_configured() then
        vim.notify("Cannot test connection: rsync is not configured. Please create a .rsync.json file or run :RsyncSetup", vim.log.levels.ERROR)
        return
    end

    vim.notify("Testing SSH connection...", vim.log.levels.INFO)

    Utils.validate_ssh_connection(function(success, message, details)
        if success then
            vim.notify("✅ " .. message, vim.log.levels.INFO)
        else
            vim.notify("❌ " .. message, vim.log.levels.ERROR)
            if details and details.errors and #details.errors > 0 then
                vim.notify("Error details: " .. table.concat(details.errors, " "), vim.log.levels.ERROR)
            end
        end
    end)
end

-- Handle diff command
function M.handle_diff_command(opts)
    -- Verify configuration before proceeding
    if not Config.is_configured() then
        vim.notify("Cannot check differences: rsync is not configured. Please create a .rsync.json file or run :RsyncSetup", vim.log.levels.ERROR)
        return
    end

    local file_path = opts.args

    if file_path == "" or file_path == nil then
        -- Use current buffer file
        file_path = vim.api.nvim_buf_get_name(0)
        if file_path == "" then
            vim.notify("No file to compare", vim.log.levels.ERROR)
            return
        end
    end

    vim.notify("Checking file differences...", vim.log.levels.INFO)

    Core.get_file_diff(file_path, nil, function(success, result)
        if success then
            if #result.changes == 0 then
                vim.notify("Files are identical", vim.log.levels.INFO)
            else
                -- Create diff buffer
                local buf = vim.api.nvim_create_buf(false, true)
                local lines = {"=== File Differences: " .. file_path .. " ===", ""}

                for _, change in ipairs(result.changes) do
                    table.insert(lines, change)
                end

                vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
                vim.api.nvim_buf_set_option(buf, "filetype", "diff")

                vim.cmd("split")
                vim.api.nvim_win_set_buf(0, buf)
                vim.api.nvim_buf_set_name(buf, "Rsync Diff")

                vim.api.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>", { noremap = true, silent = true })
            end
        else
            vim.notify("Failed to get file differences: " .. (result.message or "Unknown error"), vim.log.levels.ERROR)
        end
    end)
end

-- Handle cancel command
function M.handle_cancel_command(opts)
    local task_id = opts.args

    if task_id == "" or task_id == nil then
        -- Show active tasks and let user choose
        local status = Core.get_status()
        local active_tasks = status.active_tasks

        if #active_tasks == 0 then
            vim.notify("No active tasks to cancel", vim.log.levels.INFO)
            return
        end

        -- Create selection menu
        vim.ui.select(active_tasks, {
            prompt = "Select task to cancel:",
            format_item = function(task)
                local status_icon = task.status == "running" and "🔄" or "⏳"
                local direction_icon = task.direction == "upload" and "↑" or "↓"
                return string.format("%s [%s] %s %s", status_icon, task.id:sub(1, 8), direction_icon, task.path)
            end
        }, function(task)
            if task then
                if Core.cancel(task.id) then
                    vim.notify("Task cancelled: " .. task.id, vim.log.levels.INFO)
                else
                    vim.notify("Failed to cancel task: " .. task.id, vim.log.levels.ERROR)
                end
            end
        end)
    else
        -- Cancel specific task
        if Core.cancel(task_id) then
            vim.notify("Task cancelled: " .. task_id, vim.log.levels.INFO)
        else
            vim.notify("Failed to cancel task: " .. task_id, vim.log.levels.ERROR)
        end
    end
end

-- Helper function for upload with feedback
function M.upload_with_feedback(files)
    vim.notify(string.format("Uploading %d file(s)...", #files), vim.log.levels.INFO)

    Core.sync_files(files, "upload", {}, function(success, message)
        if success then
            vim.notify(string.format("Successfully uploaded %d file(s)", #files), vim.log.levels.INFO)
        else
            vim.notify("Upload failed: " .. (message or "Unknown error"), vim.log.levels.ERROR)
        end
    end)
end

-- Handle setup command
function M.handle_setup_command(opts)
    local Rsync = require("rsync")

    -- Check if configuration already exists
    local config_path = Config.get_config_file_path()
    if config_path then
        vim.ui.select({
            "Create new configuration (overwrite existing)",
            "Edit existing configuration",
            "Cancel"
        }, {
            prompt = "Configuration file already exists at " .. config_path,
            format_item = function(item)
                return item
            end
        }, function(choice)
            if choice == "Create new configuration (overwrite existing)" then
                Rsync.setup_interactive()
            elseif choice == "Edit existing configuration" then
                vim.cmd("edit " .. config_path)
            end
        end)
    else
        Rsync.setup_interactive()
    end
end

-- Register only basic setup command (works without configuration)
function M.register_basic_only()
    -- Configuration setup command
    vim.api.nvim_create_user_command("RsyncSetup", function(opts)
        M.handle_setup_command(opts)
    end, {
        nargs = 0,
        desc = "Interactive configuration setup for rsync-nvim"
    })
end

-- Helper function for download with feedback
function M.download_with_feedback(files)
    vim.notify(string.format("Downloading %d file(s)...", #files), vim.log.levels.INFO)

    Core.sync_files(files, "download", {}, function(success, message)
        if success then
            vim.notify(string.format("Successfully downloaded %d file(s)", #files), vim.log.levels.INFO)
        else
            vim.notify("Download failed: " .. (message or "Unknown error"), vim.log.levels.ERROR)
        end
    end)
end

return M