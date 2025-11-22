-- Test simple rsync command step by step

print("=== Step-by-step rsync test ===")

-- Step 1: Create temp file with proper content
local temp_file = "/tmp/test_files.txt"
local f = io.open(temp_file, "w")
if not f then
    print("ERROR: Cannot create temp file")
    os.exit(1)
end

-- Write an absolute path for README.md
f:write("/home/ethan/work/lua/rsync-nvim/README.md\n")
f:close()
print("✅ Created temp file:", temp_file)

-- Step 2: Test a very simple rsync command first
print("\n=== Testing basic rsync ===")
local basic_cmd = "rsync --version"
print("Command:", basic_cmd)
local result1 = os.execute(basic_cmd .. " 2>&1 | head -3")
print("Result:", result1)

-- Step 3: Test files-from option with simple command
print("\n=== Testing files-from option ===")
local simple_cmd = "rsync --files-from=" .. temp_file .. " --dry-run -v /dev/null /tmp/"
print("Command:", simple_cmd)
local result2 = os.execute(simple_cmd .. " 2>&1")
print("Result:", result2)

-- Step 4: Test our actual command structure (simplified)
print("\n=== Testing simplified version of our command ===")
local test_cmd = string.format(
    "rsync -a -z --progress --stats -p -o -g --relative --dry-run -v --files-from=%s root@8.152.204.236:~/test3/",
    temp_file
)
print("Command:", test_cmd)
local result3 = os.execute(test_cmd .. " 2>&1 | head -10")
print("Result:", result3)

-- Step 5: Test without --relative option
print("\n=== Testing without --relative ===")
local no_relative_cmd = string.format(
    "rsync -a -z --progress --stats -p -o -g --dry-run -v --files-from=%s root@8.152.204.236:~/test3/",
    temp_file
)
print("Command:", no_relative_cmd)
local result4 = os.execute(no_relative_cmd .. " 2>&1 | head -10")
print("Result:", result4)

-- Step 6: Test with explicit file instead of files-from
print("\n=== Testing with explicit file ===")
local explicit_cmd = "rsync -a -z --progress --stats -p -o -g --dry-run -v /home/ethan/work/lua/rsync-nvim/README.md root@8.152.204.236:~/test3/"
print("Command:", explicit_cmd)
local result5 = os.execute(explicit_cmd .. " 2>&1 | head -10")
print("Result:", result5)

-- Cleanup
os.remove(temp_file)
print("\n✅ Cleanup completed")