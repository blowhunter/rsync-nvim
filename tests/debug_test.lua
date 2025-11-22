-- Debug test to see the actual rsync command generated
package.path = "/home/ethan/work/lua/rsync-nvim/lua/?.lua;" .. package.path

-- Mock minimal vim environment
vim = {
    notify = function(msg, level) print("[NOTIFY] " .. msg) end,
    log = { levels = { ERROR = 1, WARN = 2, INFO = 3, DEBUG = 4 } },
    fn = {
        getcwd = function() return "/home/ethan/work/lua/rsync-nvim" end,
        findfile = function(name, path) return "/home/ethan/work/lua/rsync-nvim/.rsync.json" end,
        readfile = function(path)
            return {
                "{",
                '  "remote_path": "~/test3",',
                '  "private_key_path": "~/.ssh/id_rsa",',
                '  "host": "8.152.204.236",',
                '  "auto_sync": false,',
                '  "sync_on_save": true,',
                '  "sync_interval": 30000,',
                '  "include_patterns": [],',
                '  "port": 22,',
                '  "username": "root",',
                '  "local_path": "~/work/lua/rsync-nvim/",',
                '  "max_file_size": 10485760,',
                '  "exclude_patterns": [".git/", "*.tmp", "*.log", ".DS_Store"]',
                "}"
            }
        end,
        expand = function(path) return path:gsub("^~", "/home/ethan") end,
        filereadable = function(path) return 1 end,
        tempname = function() return "/tmp/test_rsync_file_list" end,
        writefile = function(lines, path)
            print("=== TEMP FILE CONTENT ===")
            print("File:", path)
            print("Content:")
            for i, line in ipairs(lines) do
                print(i, "'" .. line .. "'")
            end
            print("========================")
            return 0
        end,
        delete = function(path) return 0 end,
        jobstart = function(cmd, opts)
            print("=== RSYNC COMMAND ===")
            for i, arg in ipairs(cmd) do
                print(i, "'" .. arg .. "'")
            end
            print("Full command: " .. table.concat(cmd, " "))
            print("===================")

            -- Simulate calling the actual rsync to see real error
            local full_cmd = table.concat(cmd, " ")
            local result = os.execute(full_cmd .. " 2>&1")
            print("Command result:", result)

            if opts.on_exit then
                opts.on_exit(0, "")
            end
            return 12345
        end
    },
    loop = {
        fs_stat = function(path) return {type = "file", size = 1024} end
    },
    list_extend = function(dst, src)
        for _, v in ipairs(src) do table.insert(dst, v) end
    end,
    split = function(str, sep)
        local result = {}
        for match in (str .. sep):gmatch("(.-)" .. sep) do
            table.insert(result, match)
        end
        return result
    end,
    tbl_deep_extend = function(behavior, ...)
        local result = {}
        for i = 1, select("#", ...) do
            local tbl = select(i, ...)
            if type(tbl) == "table" then
                for k, v in pairs(tbl) do result[k] = v end
            end
        end
        return result
    end,
    deepcopy = function(orig)
        local orig_type = type(orig)
        local copy
        if orig_type == 'table' then
            copy = {}
            for orig_key, orig_value in next, orig, nil do
                copy[vim.deepcopy(orig_key)] = vim.deepcopy(orig_value)
            end
            setmetatable(copy, vim.deepcopy(getmetatable(orig)))
        else
            copy = orig
        end
        return copy
    end,
    defer_fn = function(fn, delay) fn() end,
    json = {
        decode = function(str)
            return {
                remote_path = "~/test3",
                private_key_path = "~/.ssh/id_rsa",
                host = "8.152.204.236",
                auto_sync = false,
                sync_on_save = true,
                sync_interval = 30000,
                include_patterns = {},
                port = 22,
                username = "root",
                local_path = "~/work/lua/rsync-nvim/",
                max_file_size = 10485760,
                exclude_patterns = {".git/", "*.tmp", "*.log", ".DS_Store"}
            }
        end
    }
}

print("=== Debug Rsync Command Generation ===")

-- Load modules
local Config = require("rsync.config")

-- Setup config
Config.setup({config_file_reminder = false})

-- Test the command building parts manually
print("\n1. SSH Options:")
local ssh_opts = Config.get_ssh_options()
print("   SSH options:", table.concat(ssh_opts, " "))

print("\n2. Rsync Options:")
local rsync_opts = Config.get_rsync_options()
print("   Rsync options:", table.concat(rsync_opts, " "))

print("\n3. Configuration Status:")
print("   Is configured:", Config.is_configured())
print("   Host:", Config.get("host"))
print("   Username:", Config.get("username"))
print("   Local path:", Config.get("local_path"))
print("   Remote path:", Config.get("remote_path"))

print("\n4. Remote Destination:")
local remote_dest = Config.get_remote_destination("~/test3/CLAUDE.md")
print("   Remote destination:", remote_dest)

print("\n5. Testing actual upload:")
local Commands = require("rsync.commands")
Commands.handle_upload_command({fargs = {"CLAUDE.md"}})

print("\n=== Debug Complete ===")