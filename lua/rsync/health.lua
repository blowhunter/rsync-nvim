-- Health check for rsync-nvim plugin
local M = {}

-- Dependencies
local Config = require("rsync.config")
local Utils = require("rsync.utils")

-- Helper function to expand ~ in paths
local function expand_path(path)
    if path:find("^~") then
        local home = os.getenv("HOME") or os.getenv("USERPROFILE")
        return home .. path:sub(2)
    end
    return path
end

-- Helper function to get file permissions in octal format
local function get_file_permissions(mode)
    -- The mode includes file type in the upper bits, we need just the permission bits
    -- Convert to octal string and extract last 3 characters
    local perm_octal = string.format("%o", mode)
    return string.sub(perm_octal, -3)
end

-- Start health check
function M.check()
    vim.health.start("rsync-nvim")

    -- Check if required tools are available
    M.check_rsync()
    M.check_ssh()
    M.check_configuration()
    M.check_plugin_dependencies()
    M.check_permissions()

    vim.health.ok("rsync-nvim health check completed")
end

-- Check rsync availability and version
function M.check_rsync()
    vim.health.start("Checking rsync...")

    -- Check if rsync command exists
    local rsync_version = vim.fn.system("rsync --version 2>/dev/null || echo 'not_found'")
    if rsync_version:match("not_found") or vim.v.shell_error ~= 0 then
        vim.health.error("rsync command not found")
        vim.health.warn("Please install rsync:")
        vim.health.warn("  Ubuntu/Debian: sudo apt install rsync")
        vim.health.warn("  macOS: brew install rsync")
        vim.health.warn("  CentOS/RHEL: sudo yum install rsync")
        return
    end

    -- Parse version
    local version_line = rsync_version:match("rsync%s+version%s+([^\n\r]+)")
    if version_line then
        vim.health.ok(string.format("rsync found: %s", version_line))
    else
        vim.health.ok("rsync found (version unknown)")
    end

    -- Check essential rsync features
    local help_output = vim.fn.system("rsync --help 2>/dev/null || echo 'no_help'")
    local features_supported = 0

    -- Check for --progress support
    if help_output:match("%-%-progress") or help_output:match("--progress") then
        vim.health.ok("rsync supports --progress flag")
        features_supported = features_supported + 1
    else
        vim.health.warn("rsync may not support --progress flag")
        vim.health.info("Progress display may be limited")
    end

    -- Check for other important features
    local essential_features = {
        {name = "checksum", pattern = "%-%-checksum|--checksum", desc = "file integrity verification"},
        {name = "delete", pattern = "%-%-delete|--delete", desc = "file deletion"},
        {name = "archive", pattern = "%-%-archive|--archive", desc = "archive mode"},
        {name = "compress", pattern = "%-%-compress|--compress|-z", desc = "compression"},
        {name = "dry%-run", pattern = "%-%-dry%-run|--dry%-run|-n", desc = "dry run mode"},
        {name = "recursive", pattern = "%-%-recursive|--recursive|-r", desc = "recursive directory sync"}
    }

    local missing_features = {}
    for _, feature in ipairs(essential_features) do
        if help_output:match(feature.pattern) then
            features_supported = features_supported + 1
        else
            table.insert(missing_features, feature.name)
        end
    end

    -- Report feature support summary
    if features_supported >= #essential_features - 1 then  -- Allow 1 missing feature
        vim.health.ok(string.format("rsync supports %d/%d essential features", features_supported, #essential_features))
    else
        vim.health.warn(string.format("rsync only supports %d/%d essential features", features_supported, #essential_features))
        if #missing_features > 0 then
            vim.health.info("Missing features: " .. table.concat(missing_features, ", "))
            vim.health.info("Consider upgrading rsync for full functionality")
        end
    end

    -- Version-based feature assurance (for modern rsync versions)
    local version_line = rsync_version:match("rsync%s+version%s+([^\n\r]+)")
    if version_line then
        local major, minor = version_line:match("(%d+)%.(%d+)")
        if major and tonumber(major) >= 3 or (tonumber(major) == 2 and tonumber(minor) >= 6) then
            vim.health.ok("rsync version is modern and supports all required features")
        end
    end
end

-- Check SSH availability and configuration
function M.check_ssh()
    vim.health.start("Checking SSH...")

    -- Check if ssh command exists
    local ssh_version = vim.fn.system("ssh -V 2>&1 || echo 'not_found'")
    if ssh_version:match("not_found") or vim.v.shell_error ~= 0 then
        vim.health.error("ssh command not found")
        vim.health.warn("Please install OpenSSH:")
        vim.health.warn("  Ubuntu/Debian: sudo apt install openssh-client")
        vim.health.warn("  macOS: system includes ssh by default")
        vim.health.warn("  CentOS/RHEL: sudo yum install openssh-clients")
        return
    end

    -- Parse SSH version
    local version_info = ssh_version:match("OpenSSH[_%s]+([^\n\r]+)")
    if version_info then
        vim.health.ok(string.format("SSH found: %s", version_info))
    else
        vim.health.ok("SSH found (version unknown)")
    end

    -- Check for SSH agent (optional but helpful)
    local ssh_agent = os.getenv("SSH_AUTH_SOCK")
    if ssh_agent and ssh_agent ~= "" then
        vim.health.ok("SSH agent is available")
    else
        vim.health.info("SSH agent not found (optional)")
        vim.health.info("Consider using ssh-agent for passwordless authentication")
    end
end

-- Check configuration file and settings
function M.check_configuration()
    vim.health.start("Checking configuration...")

    -- Get current working directory
    local current_dir = vim.fn.getcwd()
    vim.health.info(string.format("Checking configuration in directory: %s", current_dir))

    -- Check for configuration file
    local config_path = current_dir .. "/.rsync.json"
    local config_stat = vim.loop.fs_stat(config_path)

    if not config_stat then
        vim.health.info("No configuration file found in current directory")
        vim.health.info("This is normal if you haven't set up the plugin yet")
        vim.health.info("Create one with: :RsyncSetup")
        return
    end

    vim.health.ok(string.format("Configuration file found: %s", config_path))

    -- Check configuration file permissions
    local permissions = get_file_permissions(config_stat.mode)
    if config_stat.mode % 2^9 == 0 then -- Check if group/others have no permissions
        vim.health.ok(string.format("Configuration file has secure permissions (%s)", permissions))
    else
        vim.health.warn(string.format("Configuration file has insecure permissions (%s)", permissions))
        vim.health.info("Consider running: chmod 600 .rsync.json")
    end

    -- Use existing configuration validation logic
    local is_configured = Config.is_configured()
    if is_configured then
        vim.health.ok("Configuration is properly set up")
    else
        vim.health.warn("Configuration is incomplete or invalid")
    end

    -- Use existing validation result
    local validation_result = Config.validate_current_config()
    if validation_result.valid then
        vim.health.ok("Configuration validation passed")
    else
        vim.health.error("Configuration validation failed:")
        for _, error_msg in ipairs(validation_result.errors or {}) do
            vim.health.error("  " .. error_msg)
        end
        vim.health.info("Fix configuration issues with: :RsyncSetup")
    end

    -- Display current configuration values using existing Config.get()
    vim.health.info("Current configuration values:")

    local config_fields = {
        {name = "host", desc = "Remote server address", required = true},
        {name = "username", desc = "SSH username", required = true},
        {name = "port", desc = "SSH port", required = false},
        {name = "local_path", desc = "Local project path", required = true},
        {name = "remote_path", desc = "Remote project path", required = true},
        {name = "private_key_path", desc = "SSH private key path", required = false},
        {name = "sync_on_save", desc = "Auto sync on save", required = false},
        {name = "max_connections", desc = "Maximum connections", required = false},
        {name = "exclude_patterns", desc = "Exclude patterns", required = false}
    }

    for _, field in ipairs(config_fields) do
        local value = Config.get(field.name)
        if value then
            if field.name == "exclude_patterns" and type(value) == "table" then
                vim.health.ok(string.format("  %s: [%d patterns]", field.desc, #value))
            else
                local display_value = tostring(value)
                -- Truncate long values for display
                if #display_value > 30 then
                    display_value = display_value:sub(1, 27) .. "..."
                end
                vim.health.ok(string.format("  %s: %s", field.desc, display_value))
            end
        elseif field.required then
            vim.health.error(string.format("  %s: NOT SET (required)", field.desc))
        else
            vim.health.info(string.format("  %s: not set (optional)", field.desc))
        end
    end

    -- Test if configured paths are accessible
    local local_path = Config.get("local_path")
    if local_path and local_path ~= "" then
        local expanded_path = expand_path(local_path)
        local path_stat = vim.loop.fs_stat(expanded_path)
        if path_stat then
            vim.health.ok(string.format("Local path is accessible: %s", expanded_path))
        else
            vim.health.error(string.format("Local path not accessible: %s", expanded_path))
        end
    end

    local private_key_path = Config.get("private_key_path")
    if private_key_path and private_key_path ~= "" then
        local expanded_key_path = expand_path(private_key_path)
        local key_stat = vim.loop.fs_stat(expanded_key_path)
        if key_stat then
            local key_permissions = get_file_permissions(key_stat.mode)
            vim.health.ok(string.format("Private key is accessible: %s (permissions: %s)", expanded_key_path, key_permissions))
        else
            vim.health.error(string.format("Private key not found: %s", expanded_key_path))
        end
    end
end

-- Check plugin dependencies
function M.check_plugin_dependencies()
    vim.health.start("Checking plugin dependencies...")

    -- Check for required Neovim version
    if vim.fn.has("nvim-0.7.0") == 1 then
        vim.health.ok("Neovim version is supported")
    else
        vim.health.error("Neovim version 0.7.0 or higher is required")
        vim.health.warn("Please upgrade Neovim")
    end

    -- Check for required Neovim built-in modules
    local builtin_modules = {
        { name = "vim.json", check = function() return vim.json and vim.json.encode and vim.json.decode end },
        { name = "vim.loop", check = function() return vim.loop and vim.loop.fs_stat and vim.loop.hrtime end },
        { name = "vim.fn", check = function() return vim.fn and vim.fn.has and vim.fn.system end },
        { name = "vim.api", check = function() return vim.api and vim.api.nvim_create_user_command end },
        { name = "vim.ui", check = function() return vim.ui end }
    }

    for _, module in ipairs(builtin_modules) do
        if module.check() then
            vim.health.ok(string.format("Built-in module available: %s", module.name))
        else
            vim.health.error(string.format("Built-in module not available: %s (Neovim version issue)", module.name))
        end
    end

    -- Check for optional but recommended UI modules
    local optional_ui_modules = {
        { name = "vim.ui.input", check = function() return vim.ui and vim.ui.input end },
        { name = "vim.ui.select", check = function() return vim.ui and vim.ui.select end }
    }

    for _, module in ipairs(optional_ui_modules) do
        if module.check() then
            vim.health.ok(string.format("UI module available: %s", module.name))
        else
            vim.health.info(string.format("UI module not available: %s (consider installing dressing.nvim)", module.name))
            vim.health.info("  Install with: { 'stevearc/dressing.nvim', opts = {} }")
        end
    end
end

-- Check file permissions and accessibility
function M.check_permissions()
    vim.health.start("Checking permissions...")

    -- Check local path accessibility
    local local_path = Config.get("local_path")
    if local_path and local_path ~= "" then
        local stat = vim.loop.fs_stat(local_path)
        if stat then
            vim.health.ok(string.format("Local path accessible: %s", local_path))

            -- Test write permission
            local test_file = local_path .. "/.rsync_test_" .. os.time()
            local file = io.open(test_file, "w")
            if file then
                file:write("test")
                file:close()
                os.remove(test_file)
                vim.health.ok("Write permission confirmed for local path")
            else
                vim.health.warn("No write permission for local path")
            end
        else
            vim.health.error(string.format("Local path not accessible: %s", local_path))
        end
    end

    -- Helper function to expand ~ in paths
    local function expand_path(path)
        if path:find("^~") then
            local home = os.getenv("HOME") or os.getenv("USERPROFILE")
            return home .. path:sub(2)
        end
        return path
    end

  -- Check SSH key setup
    local private_key_path = Config.get("private_key_path")
    local ssh_keys_found = false

    -- Check if private key is specified in config
    if private_key_path and private_key_path ~= "" then
        local expanded_path = expand_path(private_key_path)
        local key_stat = vim.loop.fs_stat(expanded_path)
        if key_stat then
            vim.health.ok(string.format("Configured private key found: %s", expanded_path))
            ssh_keys_found = true

            -- Check SSH key permissions (should be 600 or 400)
            local permissions = get_file_permissions(key_stat.mode)
            if permissions == "600" or permissions == "400" then
                vim.health.ok(string.format("Private key has secure permissions (%s)", permissions))
            else
                vim.health.warn(string.format("Private key has insecure permissions (%s): %s", permissions, expanded_path))
                vim.health.info("SSH private keys should have permissions 600 or 400")
                vim.health.info("Run: chmod 600 " .. expanded_path)
            end
        else
            vim.health.error(string.format("Configured private key not found: %s", expanded_path))
            vim.health.info("Check if the path is correct or the file exists")
        end
    end

    -- If no private key configured, check for common SSH key locations
    if not ssh_keys_found then
        local home_dir = os.getenv("HOME") or os.getenv("USERPROFILE")
        local common_key_paths = {
            "~/.ssh/id_rsa",
            "~/.ssh/id_ed25519",
            "~/.ssh/id_ecdsa",
            "~/.ssh/id_dsa"
        }

        local found_keys = {}
        for _, key_path in ipairs(common_key_paths) do
            local expanded_path = expand_path(key_path)
            local key_stat = vim.loop.fs_stat(expanded_path)
            if key_stat then
                table.insert(found_keys, expanded_path)

                local permissions = get_file_permissions(key_stat.mode)
                if permissions == "600" or permissions == "400" then
                    vim.health.ok(string.format("SSH key found with good permissions (%s): %s", permissions, expanded_path))
                else
                    vim.health.warn(string.format("SSH key found with insecure permissions (%s): %s", permissions, expanded_path))
                    vim.health.info("SSH private keys should have permissions 600 or 400")
                    vim.health.info("Run: chmod 600 " .. expanded_path)
                end
            end
        end

        if #found_keys > 0 then
            ssh_keys_found = true
            vim.health.ok(string.format("Found %d SSH key(s) in default locations", #found_keys))
            vim.health.info("If you want to use a specific key, add to config: \"private_key_path\": \"~/.ssh/id_rsa\"")
        else
            vim.health.warn("No SSH keys found in common locations")
            vim.health.info("Generate SSH key: ssh-keygen -t ed25519 -C \"your-email@example.com\"")
            vim.health.info("Or specify custom key path in config: \"private_key_path\": \"/path/to/your/key\"")
        end
    end

    -- Check SSH agent if no local keys found
    if not ssh_keys_found then
        local ssh_agent = os.getenv("SSH_AUTH_SOCK")
        if ssh_agent and ssh_agent ~= "" then
            vim.health.ok("SSH agent is available - can use agent-stored keys")
        else
            vim.health.warn("No SSH keys found and no SSH agent running")
            vim.health.info("Start SSH agent: eval \"$(ssh-agent -s)\" && ssh-add")
        end
    end

    -- Check directory scanning capability
    local current_dir = vim.fn.getcwd()
    local files = Utils.scan_directory(current_dir, 1) -- Scan with depth 1
    if files and #files > 0 then
        vim.health.ok("Directory scanning functionality works")
    else
        vim.health.warn("Directory scanning may not work properly")
    end
end

return M