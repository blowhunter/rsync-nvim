-- Health check for rsync-nvim plugin
local M = {}

-- Dependencies
local Config = require("rsync.config")
local Utils = require("rsync.utils")

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
    local features = vim.fn.system("rsync --help 2>/dev/null | grep -E '%-%-progress|%-%-checksum|%-%-delete'")
    if features:match("%-%-progress") then
        vim.health.ok("rsync supports --progress flag")
    else
        vim.health.warn("rsync may not support --progress flag")
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

    -- Check if configuration is properly set up
    local is_configured = Config.is_configured()
    if is_configured then
        vim.health.ok("Configuration is properly set up")
    else
        vim.health.warn("Configuration not found or incomplete")
        vim.health.info("Run :RsyncSetup to configure the plugin")
    end

    -- Check for configuration file if it should exist
    local config_path = vim.fn.getcwd() .. "/.rsync.json"
    local config_stat = vim.loop.fs_stat(config_path)
    if config_stat then
        vim.health.ok(string.format("Configuration file found: %s", config_path))

        -- Check configuration file permissions
        if config_stat.mode % 2^9 == 0 then -- Check if group/others have no permissions
            vim.health.ok("Configuration file has secure permissions")
        else
            vim.health.warn("Configuration file may have insecure permissions")
            vim.health.info("Consider restricting access to your SSH configuration")
        end

        -- Validate configuration content
        local validation_result = Config.validate_current_config()
        if validation_result.valid then
            vim.health.ok("Configuration validation passed")
        else
            vim.health.error("Configuration validation failed:")
            for _, error_msg in ipairs(validation_result.errors or {}) do
                vim.health.error("  " .. error_msg)
            end
        end
    else
        vim.health.info("No configuration file found in current directory")
        vim.health.info("This is normal if you haven't set up the plugin yet")
    end

    -- Check essential configuration values
    local required_fields = {"host", "username", "local_path", "remote_path"}
    for _, field in ipairs(required_fields) do
        local value = Config.get(field)
        if value and value ~= "" then
            vim.health.ok(string.format("Configuration %s: %s", field, value:gsub("(.{1,20}).*", "%1...")))
        else
            vim.health.warn(string.format("Configuration %s not set", field))
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

    -- Check SSH key setup
    local private_key_path = Config.get("private_key_path")
    local ssh_keys_found = false

    -- Check if private key is specified in config
    if private_key_path and private_key_path ~= "" then
        local key_stat = vim.loop.fs_stat(private_key_path)
        if key_stat then
            vim.health.ok(string.format("Configured private key found: %s", private_key_path))
            ssh_keys_found = true

            -- Check SSH key permissions (should be 600 or 400)
            local permissions = string.format("%o", key_stat.mode % 1000)
            if permissions == "600" or permissions == "400" then
                vim.health.ok(string.format("Private key has secure permissions (%s)", permissions))
            else
                vim.health.warn(string.format("Private key may have insecure permissions (%s)", permissions))
                vim.health.info("SSH private keys should have permissions 600 or 400")
                vim.health.info("Run: chmod 600 " .. private_key_path)
            end
        else
            vim.health.error(string.format("Configured private key not found: %s", private_key_path))
            vim.health.info("Check if the path is correct or the file exists")
        end
    end

    -- If no private key configured, check for common SSH key locations
    if not ssh_keys_found then
        local home_dir = os.getenv("HOME") or os.getenv("USERPROFILE")
        local common_key_paths = {
            home_dir .. "/.ssh/id_rsa",
            home_dir .. "/.ssh/id_ed25519",
            home_dir .. "/.ssh/id_ecdsa",
            home_dir .. "/.ssh/id_dsa"
        }

        local found_keys = {}
        for _, key_path in ipairs(common_key_paths) do
            local key_stat = vim.loop.fs_stat(key_path)
            if key_stat then
                table.insert(found_keys, key_path)

                local permissions = string.format("%o", key_stat.mode % 1000)
                if permissions == "600" or permissions == "400" then
                    vim.health.ok(string.format("SSH key found with good permissions: %s", key_path))
                else
                    vim.health.warn(string.format("SSH key found with insecure permissions (%s): %s", permissions, key_path))
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