-- Main entry point for rsync.nvim plugin
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
    Config.setup(opts or {})

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

-- Sync single file
function M.sync_file(file_path, direction)
    direction = direction or "upload"
    return Core.sync_file(file_path, direction)
end

-- Sync multiple files
function M.sync_files(file_paths, direction)
    direction = direction or "upload"
    return Core.sync_files(file_paths, direction)
end

-- Sync directory
function M.sync_directory(dir_path, direction)
    direction = direction or "upload"
    return Core.sync_directory(dir_path, direction)
end

-- Sync all (based on config)
function M.sync_all()
    return Core.sync_all()
end

-- Get sync status
function M.get_status()
    return Pool.get_status()
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