-- Main entry point for rsync-nvim plugin
local M = {}

-- Version
M.version = "0.1.0"

-- Module dependencies
local Config = require("rsync.config")
local Core = require("rsync.core")
local Pool = require("rsync.pool")
local Commands = require("rsync.commands")
local Utils = require("rsync.utils")

-- Initialize plugin
function M.setup(opts)
    -- Initialize configuration
    local config_loaded = Config.setup(opts or {})

    -- Check if configuration file exists and show reminder if needed
    if not config_loaded and Config.get("config_file_reminder", true) then
        M.show_config_file_reminder()
    end

    -- Only proceed with setup if configuration is valid
    if not Config.is_configured() then
        vim.notify("Rsync plugin is not configured. Please create a .rsync.json file or run :RsyncSetup", vim.log.levels.WARN)
        return false
    end

    -- Initialize connection pool
    Pool.setup()

    -- Register Neovim commands
    Commands.register()

    -- Setup auto-sync if enabled
    if Config.get("auto_sync") then
        M.setup_auto_sync()
    end

    -- Setup sync on save if enabled
    if Config.get("sync_on_save") then
        M.setup_sync_on_save()
    end

    return true
end

-- Auto-sync setup
function M.setup_auto_sync()
    local interval = Config.get("sync_interval", 30000)
    local timer = vim.loop.new_timer()

    timer:start(0, interval, vim.schedule_wrap(function()
        M.sync_all()
    end))

    M._auto_sync_timer = timer
end

-- Sync on save setup
function M.setup_sync_on_save()
    local augroup = vim.api.nvim_create_augroup("RsyncSyncOnSave", { clear = true })

    vim.api.nvim_create_autocmd("BufWritePost", {
        group = augroup,
        callback = function(args)
            if M.should_sync_file(args.file) then
                M.sync_file(args.file)
            end
        end,
    })
end

-- Check if file should be synced
function M.should_sync_file(file_path)
    local local_path = Config.get("local_path")
    if not file_path:find(local_path, 1, true) then
        return false
    end

    -- Check include/exclude patterns
    local relative_path = file_path:sub(local_path:len() + 2)

    -- Check exclude patterns
    for _, pattern in ipairs(Config.get("exclude_patterns", {})) do
        if relative_path:match(pattern) then
            return false
        end
    end

    -- Check include patterns (if specified)
    local include_patterns = Config.get("include_patterns", {})
    if #include_patterns > 0 then
        for _, pattern in ipairs(include_patterns) do
            if relative_path:match(pattern) then
                return true
            end
        end
        return false
    end

    return true
end

-- Verify configuration before any sync operation
local function verify_config_for_operation(operation_name)
    if not Config.is_configured() then
        vim.notify("Cannot " .. operation_name .. ": rsync is not configured. Please create a .rsync.json file or run :RsyncSetup", vim.log.levels.ERROR)
        return false
    end

    -- Additional validation
    local validation_result = Config.validate_current_config()
    if not validation_result.valid then
        vim.notify("Configuration validation failed for " .. operation_name .. ":\n" .. table.concat(validation_result.errors, "\n"), vim.log.levels.ERROR)
        return false
    end

    return true
end

-- Sync single file
function M.sync_file(file_path, direction, options, callback)
    if not verify_config_for_operation("sync file") then
        if callback then callback(false, "Configuration not valid") end
        return false
    end

    direction = direction or "upload"
    return Core.sync_file(file_path, direction, options, callback)
end

-- Sync multiple files
function M.sync_files(file_paths, direction, options, callback)
    if not verify_config_for_operation("sync files") then
        if callback then callback(false, "Configuration not valid") end
        return false
    end

    direction = direction or "upload"
    return Core.sync_files(file_paths, direction, options, callback)
end

-- Sync directory
function M.sync_directory(dir_path, direction, options, callback)
    if not verify_config_for_operation("sync directory") then
        if callback then callback(false, "Configuration not valid") end
        return false
    end

    direction = direction or "upload"
    return Core.sync_directory(dir_path, direction, options, callback)
end

-- Sync all (based on config)
function M.sync_all(callback)
    if not verify_config_for_operation("sync all") then
        if callback then callback(false, "Configuration not valid") end
        return false
    end

    return Core.sync_all(callback)
end

-- Get sync status
function M.get_status()
    return Pool.get_status()
end

-- Show configuration file reminder
function M.show_config_file_reminder()
    local message = [[
rsync-nvim: No configuration file found!

To use rsync-nvim, you need to create a configuration file in your project root.

Quick setup:
  1. Run ':RsyncSetup' for interactive configuration setup
  2. Or create a '.rsync.json' file manually:

Example .rsync.json:
{
  "host": "your-server.com",
  "username": "your-username",
  "local_path": "~/your-project",
  "remote_path": "~/remote-project",
  "exclude_patterns": [".git/", "*.tmp", "*.log"]
}

To disable this reminder, add to your config:
  "config_file_reminder": false
]]

    vim.notify(message, vim.log.levels.WARN)
end

-- Interactive configuration setup
function M.setup_interactive()
    vim.ui.input({ prompt = "Remote host address: " }, function(host)
        if not host or host == "" then return end

        vim.ui.input({ prompt = "SSH username: " }, function(username)
            if not username or username == "" then return end

            vim.ui.input({ prompt = "Local project path: ", default = vim.fn.getcwd() }, function(local_path)
                if not local_path or local_path == "" then return end

                vim.ui.input({ prompt = "Remote project path: " }, function(remote_path)
                    if not remote_path or remote_path == "" then return end

                    -- Create configuration
                    local config = {
                        host = host,
                        username = username,
                        local_path = local_path,
                        remote_path = remote_path,
                        sync_on_save = true,
                        exclude_patterns = {".git/", "*.tmp", "*.log", ".DS_Store"}
                    }

                    -- Write configuration file
                    local config_path = vim.fn.getcwd() .. "/.rsync.json"
                    local config_json = vim.json.encode(config)

                    local file = io.open(config_path, "w")
                    if file then
                        file:write(config_json)
                        file:close()
                        vim.notify("Configuration saved to: " .. config_path, vim.log.levels.INFO)

                        -- Reload configuration
                        Config.setup()

                        -- Test connection
                        vim.notify("Testing SSH connection...", vim.log.levels.INFO)
                        Utils.validate_ssh_connection(function(success, message)
                            if success then
                                vim.notify("✅ " .. message, vim.log.levels.INFO)
                            else
                                vim.notify("❌ " .. message, vim.log.levels.ERROR)
                            end
                        end)
                    else
                        vim.notify("Failed to create configuration file", vim.log.levels.ERROR)
                    end
                end)
            end)
        end)
    end)
end

-- Cleanup
function M.cleanup()
    if M._auto_sync_timer then
        M._auto_sync_timer:close()
        M._auto_sync_timer = nil
    end
    Pool.cleanup()
end

return M