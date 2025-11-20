-- Optimized core rsync operations for rsync.nvim
local M = {}

-- Dependencies
local Config = require("rsync.config")
local Utils = require("rsync.utils")

-- Enhanced state management
local state = {
    active_transfers = {},
    transfer_history = {},
    network_stats = {
        latency = 0,
        bandwidth = 0,
        packet_loss = 0
    },
    performance_metrics = {
        total_transferred = 0,
        average_speed = 0,
        success_rate = 0
    }
}

-- File grouping strategies
local FileGroup = {
    CONFIG = "config",
    SMALL = "small",     -- < 1MB
    MEDIUM = "medium",   -- 1MB - 10MB
    LARGE = "large",     -- > 10MB
    BINARY = "binary"
}

-- Network adaptive parameters
local network_params = {
    max_connections = 3,
    timeout = 30000,
    compression_enabled = false,
    batch_size = 50
}

-- Intelligent file grouping
local function group_files_by_strategy(file_paths)
    local groups = {}

    for _, group_type in pairs(FileGroup) do
        groups[group_type] = {}
    end

    for _, file_path in ipairs(file_paths) do
        local stat = vim.loop.fs_stat(file_path)
        if not stat then goto continue end

        local size = stat.size
        local ext = file_path:match("^.+%.(.+)$") or ""
        local relative_path = Utils.get_relative_path(file_path, Config.get("local_path"))

        -- Config files have highest priority
        if is_config_file(relative_path, ext) then
            table.insert(groups[FileGroup.CONFIG], file_path)
        -- Binary files
        elseif is_binary_file(ext) then
            table.insert(groups[FileGroup.BINARY], file_path)
        -- Size-based grouping
        elseif size < 1024 * 1024 then
            table.insert(groups[FileGroup.SMALL], file_path)
        elseif size < 10 * 1024 * 1024 then
            table.insert(groups[FileGroup.MEDIUM], file_path)
        else
            table.insert(groups[FileGroup.LARGE], file_path)
        end

        ::continue::
    end

    return groups
end

-- Check if file is a configuration file
local function is_config_file(path, ext)
    local config_patterns = {
        "%.json$", "%.yaml$", "%.yml$", "%.toml$", "%.ini$",
        "%.conf$", "%.cfg$", "%.env$", "%.mk$", "^Makefile",
        "^%.gitignore$", "^%.gitattributes$", "^README", "^LICENSE"
    }

    for _, pattern in ipairs(config_patterns) do
        if path:match(pattern) then
            return true
        end
    end

    return false
end

-- Check if file is binary
local function is_binary_file(ext)
    local binary_exts = {
        "exe", "dll", "so", "dylib", "bin", "app",
        "jpg", "jpeg", "png", "gif", "bmp", "ico",
        "mp3", "mp4", "avi", "mov", "wav", "flac",
        "zip", "tar", "gz", "rar", "7z", "pdf",
        "doc", "docx", "xls", "xlsx", "ppt", "pptx"
    }

    for _, bin_ext in ipairs(binary_exts) do
        if ext:lower() == bin_ext then
            return true
        end
    end

    return false
end

-- Adaptive concurrency control
local function calculate_optimal_concurrency()
    local base_concurrency = 3

    -- Adjust based on network conditions
    if state.network_stats.latency < 50 then
        base_concurrency = base_concurrency + 2
    elseif state.network_stats.latency > 300 then
        base_concurrency = math.max(1, base_concurrency - 1)
    end

    if state.network_stats.packet_loss > 0.05 then
        base_concurrency = math.max(1, base_concurrency - 1)
    end

    -- Ensure at least 1 connection and no more than 10
    return math.max(1, math.min(10, base_concurrency))
end

-- Network measurement functions
local function measure_network_latency()
    local start_time = vim.loop.hrtime()

    Utils.validate_ssh_connection(function(success, _)
        local end_time = vim.loop.hrtime()
        local latency = (end_time - start_time) / 1000000 -- Convert to milliseconds

        if success then
            state.network_stats.latency = latency
        end
    end)
end

-- Enhanced retry mechanism
local function execute_with_retry(file_operation, context, max_retries)
    max_retries = max_retries or 3
    local attempt = 0

    local function try_operation()
        attempt = attempt + 1
        return file_operation()
    end

    local function should_retry(error_msg)
        if attempt >= max_retries then
            return false, "Max retries exceeded"
        end

        -- Determine retry strategy based on error type
        if error_msg:match("timeout") or error_msg:match("timed out") then
            return true, 2000 * attempt -- Exponential backoff for timeout
        elseif error_msg:match("connection") or error_msg:match("network") then
            return true, 3000 * attempt -- Longer backoff for connection issues
        elseif error_msg:match("disk full") or error_msg:match("no space") then
            return false, "Disk full, cannot retry" -- Don't retry disk errors
        end

        return true, 1000 -- Default retry
    end

    local function execute()
        local success, result = pcall(try_operation)

        if success then
            return true, result
        else
            local retry, delay = should_retry(result)

            if retry then
                vim.schedule(function()
                    vim.notify(string.format("操作失败，%d ms 后重试 (%d/%d): %s",
                        delay, attempt, max_retries, result), vim.log.levels.WARN)
                end)

                vim.loop.sleep(delay)
                return execute()
            else
                return false, result
            end
        end
    end

    return execute()
end

-- Intelligent file transfer with progress tracking
local function transfer_file_with_progress(file_path, direction, callback)
    local Config = require("rsync.config")

    -- Create transfer record
    local transfer_id = generate_transfer_id()
    local transfer_record = {
        id = transfer_id,
        file_path = file_path,
        direction = direction,
        start_time = os.time(),
        status = "initializing"
    }

    table.insert(state.active_transfers, transfer_record)

    -- Get file size for progress calculation
    local stat = vim.loop.fs_stat(file_path)
    local total_size = stat and stat.size or 0

    -- Build rsync command with progress tracking
    local cmd = build_rsync_command(file_path, direction)

    local transferred_bytes = 0
    local last_update = 0

    local handle = vim.fn.jobstart(cmd, {
        on_stdout = function(_, data)
            if data then
                for _, line in ipairs(data) do
                    -- Parse rsync progress output
                    local size_transferred = line:match("(%d+)%s+%d+%%%s+%d+%.%d+%s+%d+:%d+:%d+")
                    if size_transferred then
                        transferred_bytes = tonumber(size_transferred)

                        local current_time = os.time()
                        if current_time - last_update >= 1 then -- Update every second
                            local progress = total_size > 0 and (transferred_bytes / total_size) * 100 or 0
                            transfer_record.progress = progress
                            transfer_record.transferred_bytes = transferred_bytes
                            transfer_record.status = "transferring"

                            if callback and callback.on_progress then
                                callback.on_progress(transfer_record)
                            end

                            last_update = current_time
                        end
                    end
                end
            end
        end,
        on_stderr = function(_, data)
            if data and callback and callback.on_error then
                callback.on_error(table.concat(data, "\n"))
            end
        end,
        on_exit = function(_, exit_code)
            transfer_record.end_time = os.time()
            transfer_record.status = exit_code == 0 and "completed" or "failed"
            transfer_record.exit_code = exit_code

            -- Move to history
            table.insert(state.transfer_history, transfer_record)

            -- Remove from active transfers
            for i, active in ipairs(state.active_transfers) do
                if active.id == transfer_id then
                    table.remove(state.active_transfers, i)
                    break
                end
            end

            -- Update metrics
            update_performance_metrics(transfer_record)

            if callback and callback.on_complete then
                callback.on_complete(exit_code == 0, transfer_record)
            end
        end
    })

    if handle <= 0 then
        transfer_record.status = "failed"
        transfer_record.error = "Failed to start rsync process"
        return false, "Failed to start rsync process"
    end

    transfer_record.handle = handle
    return transfer_id
end

-- Build optimized rsync command
local function build_rsync_command(file_path, direction)
    local Config = require("rsync.config")

    local cmd = {"rsync"}

    -- Add base options
    vim.list_extend(cmd, Config.get_rsync_options())

    -- Add network-adaptive options
    if network_params.compression_enabled then
        table.insert(cmd, "-z")
    end

    -- Add SSH options
    vim.list_extend(cmd, {"-e", "ssh " .. table.concat(Config.get_ssh_options(), " ")})

    -- Add timeout
    table.insert(cmd, "--timeout=" .. math.floor(network_params.timeout / 1000))

    -- Add progress tracking
    table.insert(cmd, "--progress")

    -- Add source and destination
    local source, destination
    if direction == "upload" then
        source = file_path
        destination = Config.get_remote_destination(file_path)
    else
        source = Config.get_remote_destination(file_path)
        destination = file_path
    end

    table.insert(cmd, source)
    table.insert(cmd, destination)

    return cmd
end

-- Update performance metrics
local function update_performance_metrics(transfer_record)
    if transfer_record.status ~= "completed" then return end

    local duration = transfer_record.end_time - transfer_record.start_time
    local size = transfer_record.transferred_bytes or 0
    local speed = duration > 0 and size / duration or 0

    -- Update rolling average
    local alpha = 0.1 -- Smoothing factor
    state.performance_metrics.average_speed =
        state.performance_metrics.average_speed * (1 - alpha) + speed * alpha

    -- Update success rate
    local total_transfers = #state.transfer_history
    local successful_transfers = 0

    for _, record in ipairs(state.transfer_history) do
        if record.status == "completed" then
            successful_transfers = successful_transfers + 1
        end
    end

    state.performance_metrics.success_rate =
        total_transfers > 0 and (successful_transfers / total_transfers) * 100 or 0
end

-- Generate unique transfer ID
local function generate_transfer_id()
    return string.format("%d_%d", os.time(), math.random(10000, 99999))
end

-- Main optimized sync function
function M.optimized_sync(file_paths, direction, options, callback)
    if not file_paths or #file_paths == 0 then
        if callback then callback(false, "No files to sync") end
        return false
    end

    -- Measure network conditions
    measure_network_latency()

    -- Update adaptive parameters
    network_params.max_connections = calculate_optimal_concurrency()
    network_params.compression_enabled = state.network_stats.latency > 100

    -- Group files by strategy
    local file_groups = group_files_by_strategy(file_paths)

    -- Process groups in priority order
    local priority_order = {
        FileGroup.CONFIG,
        FileGroup.SMALL,
        FileGroup.MEDIUM,
        FileGroup.BINARY,
        FileGroup.LARGE
    }

    local transfer_ids = {}
    local total_groups = 0
    local completed_groups = 0

    local function process_group(group_type)
        local group_files = file_groups[group_type]
        if #group_files == 0 then return end

        total_groups = total_groups + 1

        -- For config files, process immediately
        if group_type == FileGroup.CONFIG then
            for _, file_path in ipairs(group_files) do
                local transfer_id = transfer_file_with_progress(file_path, direction, callback)
                table.insert(transfer_ids, transfer_id)
            end
        else
            -- For other groups, use batch processing
            M.process_batch_group(group_files, direction, callback, function()
                completed_groups = completed_groups + 1
                if completed_groups == total_groups and callback and callback.on_all_complete then
                    callback.on_all_complete(transfer_ids)
                end
            end)
        end
    end

    -- Process all groups
    for _, group_type in ipairs(priority_order) do
        process_group(group_type)
    end

    return transfer_ids
end

-- Process file batch with optimized strategy
function M.process_batch_group(files, direction, callback, on_batch_complete)
    local batch_size = math.min(#files, network_params.batch_size)
    local processed_files = 0

    local function process_next_batch()
        if processed_files >= #files then
            if on_batch_complete then on_batch_complete() end
            return
        end

        local batch_end = math.min(processed_files + batch_size, #files)
        local current_batch = {}

        for i = processed_files + 1, batch_end do
            table.insert(current_batch, files[i])
        end

        -- Process batch with concurrent execution
        local batch_transfer_ids = {}
        local batch_completed = 0

        for _, file_path in ipairs(current_batch) do
            local transfer_id = transfer_file_with_progress(file_path, direction, {
                on_complete = function(success, record)
                    batch_completed = batch_completed + 1
                    if batch_completed == #current_batch then
                        processed_files = processed_files + #current_batch
                        -- Small delay between batches
                        vim.defer_fn(process_next_batch, 100)
                    end
                end
            })
            table.insert(batch_transfer_ids, transfer_id)
        end
    end

    process_next_batch()
end

-- Get comprehensive status
function M.get_enhanced_status()
    return {
        active_transfers = vim.deepcopy(state.active_transfers),
        transfer_history = vim.deepcopy(state.transfer_history),
        network_stats = vim.deepcopy(state.network_stats),
        performance_metrics = vim.deepcopy(state.performance_metrics),
        adaptive_params = vim.deepcopy(network_params)
    }
end

-- Adapt to network conditions
function M.adapt_to_network_conditions()
    -- Measure current network conditions
    measure_network_latency()

    -- Adjust parameters based on network stats
    if state.network_stats.latency > 300 then
        network_params.compression_enabled = true
        network_params.timeout = 60000
        network_params.batch_size = 20
    elseif state.network_stats.packet_loss > 0.05 then
        network_params.max_connections = 1
        network_params.timeout = 90000
    end

    vim.notify(string.format("Network adaptation: latency=%dms, compression=%s, connections=%d",
        state.network_stats.latency,
        network_params.compression_enabled and "enabled" or "disabled",
        network_params.max_connections), vim.log.levels.INFO)
end

return M