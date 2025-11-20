-- Configuration management for rsync-nvim
local M = {}

-- Default configuration
local default_config = {
    -- Configuration management
    config_file_reminder = true,

    -- Connection settings
    host = "",
    username = "",
    port = 22,
    private_key_path = "~/.ssh/id_rsa",

    -- Path settings
    local_path = "",
    remote_path = "",

    -- Sync behavior
    auto_sync = false,
    sync_on_save = true,
    sync_interval = 30000, -- 30 seconds

    -- File filtering
    include_patterns = {},
    exclude_patterns = {".git/", "*.tmp", "*.log", ".DS_Store"},
    max_file_size = 10485760, -- 10MB

    -- Performance settings
    max_connections = 5,
    batch_size = 50,
    connection_timeout = 30000,

    -- Rsync options
    rsync_options = {
        archive = true,        -- -a archive mode
        compress = true,       -- -z compression
        progress = true,       -- --progress
        stats = true,          -- --stats
        delete = false,        -- --delete
        checksum = false,      -- -c skip based on checksum
        verbose = false,       -- -v verbose
    }
}

-- Current configuration
local config = {}

-- Expand path (~) to full path
local function expand_path(path)
    if path:find("^~") then
        return os.getenv("HOME") .. path:sub(2)
    end
    return path
end

-- Validate configuration
local function validate_config(cfg)
    local errors = {}

    -- Required fields
    if not cfg.host or cfg.host == "" then
        table.insert(errors, "host is required")
    end

    if not cfg.local_path or cfg.local_path == "" then
        table.insert(errors, "local_path is required")
    end

    if not cfg.remote_path or cfg.remote_path == "" then
        table.insert(errors, "remote_path is required")
    end

    -- Path expansion and validation
    if cfg.local_path then
        cfg.local_path = expand_path(cfg.local_path)
        -- Check if local path exists
        local stat = vim.loop.fs_stat(cfg.local_path)
        if not stat then
            table.insert(errors, "local_path does not exist: " .. cfg.local_path)
        end
    end

    if cfg.private_key_path then
        cfg.private_key_path = expand_path(cfg.private_key_path)
        local stat = vim.loop.fs_stat(cfg.private_key_path)
        if not stat then
            table.insert(errors, "private_key_path does not exist: " .. cfg.private_key_path)
        end
    end

    -- Port validation
    if cfg.port and (cfg.port < 1 or cfg.port > 65535) then
        table.insert(errors, "port must be between 1 and 65535")
    end

    -- Performance settings validation
    if cfg.max_connections and cfg.max_connections < 1 then
        table.insert(errors, "max_connections must be at least 1")
    end

    if cfg.batch_size and cfg.batch_size < 1 then
        table.insert(errors, "batch_size must be at least 1")
    end

    return #errors == 0, errors
end

-- Load configuration from project file
local function load_project_config()
    local config_files = {
        ".rsync.json",
        ".rsync.jsonc",
        "rsync.json",
        "rsync.jsonc"
    }

    for _, filename in ipairs(config_files) do
        local config_path = vim.fn.findfile(filename, vim.fn.getcwd() .. ";")
        if config_path ~= "" then
            local content = vim.fn.readfile(config_path)
            local json_str = table.concat(content, "\n")

            -- Handle JSONC comments (strip them)
            json_str = json_str:gsub("//.-\n", "\n"):gsub("/%*.-%*/", "")

            local ok, json_config = pcall(vim.json.decode, json_str)
            if ok then
                return json_config
            else
                vim.notify("Failed to parse rsync config file: " .. config_path, vim.log.levels.ERROR)
            end
        end
    end

    return {}
end

-- Setup configuration
function M.setup(user_config)
    -- Load project config if exists
    local project_config = load_project_config()
    local config_file_exists = next(project_config) ~= nil

    -- Merge configurations: default -> project -> user
    config = vim.tbl_deep_extend("force", default_config, project_config, user_config or {})

    -- Return false if no config file loaded and user didn't provide config
    if not config_file_exists and not user_config then
        return false
    end

    -- Only validate if we have actual configuration data
    local should_validate = config_file_exists or user_config

    if should_validate then
        -- Validate configuration
        local valid, errors = validate_config(config)
        if not valid then
            vim.notify("Configuration validation failed:\n" .. table.concat(errors, "\n"), vim.log.levels.ERROR)
            return false
        end

        if config_file_exists then
            vim.notify("Rsync configuration loaded from project file", vim.log.levels.INFO)
        elseif user_config then
            vim.notify("Rsync configuration loaded from user config", vim.log.levels.INFO)
        end
    end

    return should_validate
end

-- Check if rsync is properly configured
function M.is_configured()
    -- Check required fields
    local required_fields = {"host", "username", "local_path", "remote_path"}

    for _, field in ipairs(required_fields) do
        local value = M.get(field)
        if not value or value == "" then
            return false
        end
    end

    return true
end

-- Validate current configuration and return detailed results
function M.validate_current_config()
    return validate_config(config)
end

-- Get configuration file path
function M.get_config_file_path()
    local config_files = {
        ".rsync.json",
        ".rsync.jsonc",
        "rsync.json",
        "rsync.jsonc"
    }

    for _, filename in ipairs(config_files) do
        local config_path = vim.fn.findfile(filename, vim.fn.getcwd() .. ";")
        if config_path ~= "" then
            return config_path
        end
    end

    return nil
end

-- Get configuration value
function M.get(key, default_value)
    if key == nil then
        return config
    end

    local keys = vim.split(key, ".", { plain = true })
    local value = config

    for _, k in ipairs(keys) do
        if type(value) ~= "table" or value[k] == nil then
            return default_value
        end
        value = value[k]
    end

    return value
end

-- Set configuration value
function M.set(key, value)
    local keys = vim.split(key, ".", { plain = true })
    local target = config

    for i = 1, #keys - 1 do
        if type(target[keys[i]]) ~= "table" then
            target[keys[i]] = {}
        end
        target = target[keys[i]]
    end

    target[keys[#keys]] = value
end

-- Get rsync command options
function M.get_rsync_options()
    local options = {}
    local rsync_opts = config.rsync_options

    if rsync_opts.archive then table.insert(options, "-a") end
    if rsync_opts.compress then table.insert(options, "-z") end
    if rsync_opts.progress then table.insert(options, "--progress") end
    if rsync_opts.stats then table.insert(options, "--stats") end
    if rsync_opts.delete then table.insert(options, "--delete") end
    if rsync_opts.checksum then table.insert(options, "-c") end
    if rsync_opts.verbose then table.insert(options, "-v") end

    -- Add permission preservation
    table.insert(options, "-p")  -- preserve permissions
    table.insert(options, "-o")  -- preserve owner
    table.insert(options, "-g")  -- preserve group

    return options
end

-- Get SSH options
function M.get_ssh_options()
    local options = {
        "-p", config.port,
        "-i", config.private_key_path,
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "ConnectTimeout=" .. math.floor(config.connection_timeout / 1000)
    }

    return options
end

-- Get remote destination string
function M.get_remote_destination(path)
    local user_host = config.username .. "@" .. config.host
    return user_host .. ":" .. path
end

-- Check if file size is within limits
function M.is_file_size_allowed(file_path)
    local max_size = config.max_file_size
    if max_size <= 0 then return true end

    local stat = vim.loop.fs_stat(file_path)
    if not stat then return false end

    return stat.size <= max_size
end

return M