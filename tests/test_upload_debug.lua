-- Debug upload with detailed output

print("=== DEBUG UPLOAD ===")

-- Mock vim with debug output
vim = {
    notify = function(msg, level)
        local level_name = level or 3
        local level_text = "INFO"
        if level_name == 1 then level_text = "ERROR"
        elseif level_name == 2 then level_text = "WARN"
        elseif level_name == 4 then level_text = "DEBUG"
        end
        print("[" .. level_text .. "] " .. msg)
    end,
    log = { levels = { ERROR = 1, WARN = 2, INFO = 3, DEBUG = 4 } },
    fn = {
        getcwd = function() return "/home/ethan/work/lua/rsync-nvim" end,
        findfile = function(name, path) return "/home/ethan/work/lua/rsync-nvim/.rsync.json" end,
        readfile = function(path)
            return {
                "{", '  "remote_path": "~/test3",', '  "private_key_path": "~/.ssh/id_rsa",', '  "host": "8.152.204.236",', '  "auto_sync": false,', '  "sync_on_save": true,', '  "sync_interval": 30000,', '  "include_patterns": [],', '  "port": 22,', '  "username": "root",', '  "local_path": "~/work/lua/rsync-nvim/",', '  "max_file_size": 10485760,', '  "exclude_patterns": [".git/", "*.tmp", "*.log", ".DS_Store"]', "}"
            }
        end,
        expand = function(path) return path:gsub("^~", "/home/ethan") end,
        filereadable = function(path) return path:match("README%.md$") and 1 or 0 end,
        tempname = function() return "/tmp/debug_test_file" end,
        writefile = function(lines, path)
            print("WRITE FILE:", path)
            for i, line in ipairs(lines) do
                print("  " .. i .. ": " .. line)
            end
            return 0
        end,
        delete = function(path) return 0 end,
        jobstart = function(cmd, opts)
            print("=== RSYNC COMMAND ===")
            for i, arg in ipairs(cmd) do
                print(string.format("%2d: '%s'", i, arg))
            end
            print("FULL: " .. table.concat(cmd, " "))
            print("===================")

            -- Simulate rsync execution with our test
            if cmd[1] == "rsync" then
                -- Extract the files-from parameter
                local temp_file = nil
                local local_path = nil
                for i, arg in ipairs(cmd) do
                    if arg:match("--files-from=") then
                        temp_file = arg:match("--files-from=(.+)")
                    elseif not arg:match("^%-") and not arg:match("=") and not arg:match("@") and not arg:match(":") and i > 5 then
                        if not local_path then local_path = arg end
                    end
                end

                if temp_file and local_path then
                    -- Test with actual rsync command but dry-run
                    local test_cmd = "rsync --files-from=" .. temp_file .. " " .. local_path .. " /tmp/test_dest --dry-run -v 2>&1"
                    print("TEST COMMAND:", test_cmd)
                    local result = io.popen(test_cmd):read("*a")
                    print("RSYNC OUTPUT:", result)

                    if result:match("rsync error") then
                        if opts.on_exit then opts.on_exit(1, "rsync syntax error") end
                    else
                        if opts.on_exit then opts.on_exit(0, "Success") end
                    end
                else
                    if opts.on_exit then opts.on_exit(0, "Test success") end
                end
            end

            return 12345
        end
    },
    loop = {
        fs_stat = function(path)
            -- Mock the paths that should exist
            if path:match("/home/ethan/work/lua/rsync%-nvim") then
                return {type = "directory", size = 4096}
            elseif path:match("/home/ethan/%.ssh/id_rsa") then
                return {type = "file", size = 1679}
            end
            return {type = "file", size = 1024}
        end
    },
    list_extend = function(dst, src) for _, v in ipairs(src) do table.insert(dst, v) end end,
    split = function(str, sep) local result = {} for match in (str .. sep):gmatch("(.-)" .. sep) do table.insert(result, match) end return result end,
    tbl_deep_extend = function(behavior, ...) local result = {} for i = 1, select("#", ...) do local tbl = select(i, ...) if type(tbl) == "table" then for k, v in pairs(tbl) do result[k] = v end end end return result end,
    deepcopy = function(orig) if type(orig) ~= "table" then return orig else local copy = {} for k, v in pairs(orig) do copy[k] = vim.deepcopy(v) end return copy end end,
    defer_fn = function(fn, delay) fn() end,
    json = {
        decode = function(str)
            return {
                remote_path = "~/test3", private_key_path = "~/.ssh/id_rsa", host = "8.152.204.236", auto_sync = false, sync_on_save = true, sync_interval = 30000, include_patterns = {}, port = 22, username = "root", local_path = "~/work/lua/rsync-nvim/", max_file_size = 10485760, exclude_patterns = {".git/", "*.tmp", "*.log", ".DS_Store"}
            }
        end
    }
}

-- Load and test
package.path = "/home/ethan/work/lua/rsync-nvim/lua/?.lua;" .. package.path

local Config = require("rsync.config")
Config.setup({config_file_reminder = false})

print("\n=== CONFIG STATUS ===")
print("Is configured:", Config.is_configured())
print("Local path:", Config.get("local_path"))

print("\n=== TESTING UPLOAD ===")
local Commands = require("rsync.commands")
Commands.handle_upload_command({fargs = {"README.md"}})

print("\n=== DEBUG COMPLETE ===")