-- 简化测试：直接显示实际的rsync命令

print("=== 简化 RsyncUpload 测试 ===")

-- 设置基本vim模拟
vim = {
    notify = function(msg, level)
        print("[LOG] " .. msg)
    end,
    log = { levels = { ERROR = 1, WARN = 2, INFO = 3, DEBUG = 4 } },
    fn = {
        getcwd = function() return "/home/ethan/work/lua/rsync-nvim" end,
        findfile = function() return "/home/ethan/work/lua/rsync-nvim/.rsync.json" end,
        readfile = function()
            local f = io.open("/home/ethan/work/lua/rsync-nvim/.rsync.json", "r")
            if f then
                local content = f:read("*a")
                f:close()
                return vim.split(content, "\n")
            end
            return {}
        end,
        expand = function(path) return path:gsub("^~", "/home/ethan") end,
        filereadable = function(path) return path:match("README%.md$") and 1 or 0 end,
        tempname = function() return "/tmp/simple_test" end,
        writefile = function(lines, path)
            print("写入临时文件:", path)
            for i, line in ipairs(lines) do
                print("  " .. line)
            end
            return 0
        end,
        delete = function() return 0 end,
        jobstart = function(cmd, opts)
            print("=== ACTUAL RSYNC COMMAND ===")
            for i, arg in ipairs(cmd) do
                print(string.format("%2d: %s", i, arg))
            end
            local full_cmd = table.concat(cmd, " ")
            print("FULL:", full_cmd)
            print("=============================")

            -- 模拟成功
            vim.defer_fn(function()
                if opts.on_exit then opts.on_exit(0, "Success") end
            end, 10)

            return 12345
        end
    },
    loop = {
        fs_stat = function(path)
            if path:match("work/lua/rsync%-nvim") then
                return {type = "directory", size = 4096}
            elseif path:match("%.ssh/id_rsa") then
                return {type = "file", size = 1679}
            end
            return nil
        end
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
        if type(orig) ~= "table" then return orig end
        local copy = {}
        for k, v in pairs(orig) do copy[k] = vim.deepcopy(v) end
        return copy
    end,
    defer_fn = function(fn, delay) fn() end,
    json = {
        decode = function(str)
            -- 直接返回正确的配置
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

-- 加载并测试
package.path = "/home/ethan/work/lua/rsync-nvim/lua/?.lua;" .. package.path

print("\n1. 加载配置...")
local Config = require("rsync.config")
local setup_result = Config.setup({config_file_reminder = false})
print("   配置加载结果:", setup_result)
print("   是否已配置:", Config.is_configured())

print("\n2. 检查关键配置...")
print("   Host:", Config.get("host"))
print("   Username:", Config.get("username"))
print("   Local path:", Config.get("local_path"))
print("   Private key:", Config.get("private_key_path"))

print("\n3. 强制设置配置进行测试...")
-- 强制设置配置值
Config.set("host", "8.152.204.236")
Config.set("username", "root")
Config.set("local_path", "/home/ethan/work/lua/rsync-nvim/")
Config.set("remote_path", "~/test3")
Config.set("private_key_path", "~/.ssh/id_rsa")
Config.set("port", 22)

print("   强制设置后的配置:")
print("   Host:", Config.get("host"))
print("   Username:", Config.get("username"))
print("   Local path:", Config.get("local_path"))
print("   Is configured:", Config.is_configured())

print("\n4. 测试上传命令...")
local Commands = require("rsync.commands")
Commands.handle_upload_command({fargs = {"README.md"}})

print("\n=== 测试完成 ===")