-- 直接测试rsync命令生成，绕过配置验证

print("=== 直接测试 Rsync 命令生成 ===")

-- 完整vim模拟
vim = {
    notify = function(msg) print("[LOG] " .. msg) end,
    log = { levels = { ERROR = 1, WARN = 2, INFO = 3, DEBUG = 4 } },
    list_extend = function(dst, src)
        for _, v in ipairs(src) do table.insert(dst, v) end
    end,
    fn = {
        tempname = function() return "/tmp/direct_test" end,
        writefile = function(lines, path)
            print("写入文件:", path)
            for i, line in ipairs(lines) do print("  ", line) end
            return 0
        end,
        delete = function() return 0 end,
        jobstart = function(cmd, opts)
            print("=== RSYNC COMMAND ===")
            for i, arg in ipairs(cmd) do
                print(string.format("%2d: %s", i, arg))
            end
            print("FULL:", table.concat(cmd, " "))
            print("===================")

            -- 模拟成功
            if opts.on_exit then opts.on_exit(0, "Success") end
            return 12345
        end
    },
    defer_fn = function(fn, delay) fn() end,
    split = function(str, sep)
        local result = {}
        for match in (str .. sep):gmatch("(.-)" .. sep) do
            table.insert(result, match)
        end
        return result
    end
}

package.path = "/home/ethan/work/lua/rsync-nvim/lua/?.lua;" .. package.path

-- 直接加载pool模块进行测试
local Pool = require("rsync.pool")

-- 模拟config对象
local mock_config = {
    get = function(key, default)
        local values = {
            local_path = "/home/ethan/work/lua/rsync-nvim/",
            max_connections = 5,
            batch_size = 50
        }
        return values[key] or default
    end,
    get_remote_destination = function(path)
        return "root@8.152.204.236:" .. (path or "~/test3/")
    end,
    get_ssh_options = function()
        return {"-P", "22", "-i", "/home/ethan/.ssh/id_rsa", "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null", "-o", "ConnectTimeout=30"}
    end,
    get_rsync_options = function()
        return {"-a", "-z", "--progress", "--stats", "-p", "-o", "-g"}
    end,
    get = function(key)
        local exclude_patterns = {".git/", "*.tmp", "*.log", ".DS_Store"}
        if key == "exclude_patterns" then return exclude_patterns end
        return nil
    end
}

-- 临时替换config模块
package.loaded["rsync.config"] = mock_config

print("\n1. 模拟单个文件上传任务...")
Pool.setup()

-- 创建一个上传任务
local task_id = Pool.add_task("file", "README.md", "upload", {
    remote_path = "~/test3/"
}, function(success, message, task)
    print("任务回调:")
    print("  成功:", success)
    print("  消息:", message)
    print("  任务ID:", task.id)
end)

print("   创建任务ID:", task_id)

print("\n=== 等待任务处理... ===")

-- 给任务时间处理
vim.defer_fn(function()
    print("\n2. 检查任务状态...")
    local status = Pool.get_status()
    print("   任务状态:", vim.inspect(status))
end, 100)