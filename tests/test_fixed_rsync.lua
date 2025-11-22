-- Test the fixed rsync command structure

-- Mock vim functions
vim = {
    list_extend = function(dst, src)
        for _, v in ipairs(src) do table.insert(dst, v) end
    end
}

print("=== Testing Fixed rsync Command ===")

-- Build the command with the fixed structure
local cmd = {"rsync"}

-- Add rsync options
vim.list_extend(cmd, {"-a", "-z", "--progress", "--stats", "-p", "-o", "-g"})

-- Add exclude patterns
vim.list_extend(cmd, {"--exclude=.git/", "--exclude=*.tmp", "--exclude=*.log", "--exclude=.DS_Store"})

-- Add custom options
vim.list_extend(cmd, {"--relative"})

-- Add SSH command
local ssh_cmd = "ssh -P 22 -i /home/ethan/.ssh/id_rsa -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30"
vim.list_extend(cmd, {"-e", ssh_cmd})

-- Add source and destination (FIXED VERSION)
local temp_file = "/tmp/test_file_list"
local local_path = "/home/ethan/work/lua/rsync-nvim/"  -- This is the key fix!
vim.list_extend(cmd, {"--files-from=" .. temp_file, local_path})  -- Add local path as source
vim.list_extend(cmd, {"root@8.152.204.236:~/test3/"})  -- Destination

print("Fixed command:")
for i, arg in ipairs(cmd) do
    print(i, "'" .. arg .. "'")
end

print("\nFull command:", table.concat(cmd, " "))

-- Test with a simple file
local file_list = {"README.md"}
local f = io.open(temp_file, "w")
if f then
    for _, file in ipairs(file_list) do
        f:write(file .. "\n")
    end
    f:close()
    print("Created temp file:", temp_file)

    -- Test the command (dry run)
    local test_cmd = table.concat(cmd, " ") .. " --dry-run -v"
    print("\nTesting fixed command (dry run):")
    print(test_cmd)
    local result = os.execute(test_cmd .. " 2>&1 | head -10")
    print("Result:", result)

    -- Clean up
    os.remove(temp_file)
else
    print("Failed to create temp file")
end

print("\n=== Test Complete ===")