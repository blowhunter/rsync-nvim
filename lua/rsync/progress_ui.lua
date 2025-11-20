-- Progress UI and user feedback for rsync.nvim
local M = {}

-- UI state
local ui_state = {
    progress_window = nil,
    progress_buffer = nil,
    timer = nil,
    transfer_details = {}
}

-- Create progress window
function M.create_progress_window()
    -- Close existing window if any
    M.close_progress_window()

    -- Create buffer
    ui_state.progress_buffer = vim.api.nvim_create_buf(false, true)

    -- Configure buffer
    vim.api.nvim_buf_set_option(ui_state.progress_buffer, "modifiable", true)
    vim.api.nvim_buf_set_option(ui_state.progress_buffer, "buftype", "nofile")
    vim.api.nvim_buf_set_option(ui_state.progress_buffer, "filetype", "rsync-progress")

    -- Window configuration
    local width = math.min(80, vim.fn.winwidth(0) - 10)
    local height = 15
    local win_config = {
        relative = "editor",
        width = width,
        height = height,
        col = math.floor((vim.fn.winwidth(0) - width) / 2),
        row = math.floor((vim.fn.winheight(0) - height) / 2),
        border = "rounded",
        style = "minimal",
        title = " Rsync Transfer Progress ",
        title_pos = "center"
    }

    -- Create window
    ui_state.progress_window = vim.api.nvim_open_win(ui_state.progress_buffer, false, win_config)

    -- Set up keymaps
    local opts = { noremap = true, silent = true }
    vim.api.nvim_buf_set_keymap(ui_state.progress_buffer, "n", "q", ":lua require('rsync.progress_ui').close_progress_window()<CR>", opts)
    vim.api.nvim_buf_set_keymap(ui_state.progress_buffer, "n", "<Esc>", ":lua require('rsync.progress_ui').close_progress_window()<CR>", opts)

    -- Start update timer
    ui_state.timer = vim.loop.new_timer()
    ui_state.timer:start(0, 500, vim.schedule_wrap(function()
        M.update_progress_display()
    end))

    return ui_state.progress_window
end

-- Update progress display
function M.update_progress_display()
    if not ui_state.progress_buffer or not vim.api.nvim_buf_is_valid(ui_state.progress_buffer) then
        return
    end

    local OptimizedCore = require("rsync.optimized_core")
    local status = OptimizedCore.get_enhanced_status()

    -- Build display lines
    local lines = {}

    -- Header
    table.insert(lines, "═" .. string.rep("═", 76) .. "═")
    table.insert(lines, "  Active Transfers")
    table.insert(lines, "═" .. string.rep("═", 76) .. "═")

    -- Active transfers
    if #status.active_transfers == 0 then
        table.insert(lines, "  No active transfers")
    else
        for _, transfer in ipairs(status.active_transfers) do
            local file_name = vim.fn.fnamemodify(transfer.file_path, ":t")
            local direction_icon = transfer.direction == "upload" and "↑" or "↓"
            local status_icon = get_status_icon(transfer.status)

            -- Progress bar
            local progress = transfer.progress or 0
            local progress_bar = create_progress_bar(progress, 40)

            local line = string.format("  %s [%-20s] %s %s %3.0f%%",
                status_icon,
                file_name,
                direction_icon,
                progress_bar,
                progress
            )
            table.insert(lines, line)

            -- Size info
            if transfer.transferred_bytes then
                local size_str = format_size(transfer.transferred_bytes)
                table.insert(lines, string.format("  │ %s transferred", size_str))
            end
        end
    end

    table.insert(lines, "")

    -- Network status
    table.insert(lines, "═" .. string.rep("═", 76) .. "═")
    table.insert(lines, "  Network Status")
    table.insert(lines, "═" .. string.rep("═", 76) .. "═")

    table.insert(lines, string.format("  • Latency:     %d ms", status.network_stats.latency))
    table.insert(lines, string.format("  • Connections: %d / %d",
        #status.active_transfers, status.adaptive_params.max_connections))
    table.insert(lines, string.format("  • Compression: %s",
        status.adaptive_params.compression_enabled and "Enabled" or "Disabled"))

    table.insert(lines, "")

    -- Performance metrics
    table.insert(lines, "═" .. string.rep("═", 76) .. "═")
    table.insert(lines, "  Performance")
    table.insert(lines, "═" .. string.rep("═", 76) .. "═")

    if status.performance_metrics.average_speed > 0 then
        table.insert(lines, string.format("  • Avg Speed:   %s/s",
            format_size(status.performance_metrics.average_speed)))
    end

    table.insert(lines, string.format("  • Success Rate: %.1f%%", status.performance_metrics.success_rate))

    -- Update buffer
    vim.api.nvim_buf_set_lines(ui_state.progress_buffer, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(ui_state.progress_buffer, "modifiable", false)
end

-- Create progress bar
local function create_progress_bar(percentage, width)
    local filled = math.floor((percentage / 100) * width)
    local empty = width - filled

    return "[" .. string.rep("█", filled) .. string.rep("░", empty) .. "]"
end

-- Get status icon
local function get_status_icon(status)
    local icons = {
        initializing = "⏳",
        transferring = "🔄",
        completed = "✅",
        failed = "❌",
        paused = "⏸️"
    }

    return icons[status] or "❓"
end

-- Format file size
local function format_size(bytes)
    if not bytes or bytes == 0 then return "0 B" end

    local units = {"B", "KB", "MB", "GB", "TB"}
    local size = bytes
    local unit_index = 1

    while size >= 1024 and unit_index < #units do
        size = size / 1024
        unit_index = unit_index + 1
    end

    return string.format("%.1f %s", size, units[unit_index])
end

-- Add transfer to track
function M.track_transfer(transfer_id, file_path, direction)
    ui_state.transfer_details[transfer_id] = {
        file_path = file_path,
        direction = direction,
        start_time = os.time()
    }

    -- Auto-show window if not already visible
    if not ui_state.progress_window then
        M.create_progress_window()
    end
end

-- Update transfer progress
function M.update_transfer_progress(transfer_id, progress, transferred_bytes)
    local transfer = ui_state.transfer_details[transfer_id]
    if transfer then
        transfer.progress = progress
        transfer.transferred_bytes = transferred_bytes
        transfer.last_update = os.time()
    end
end

-- Complete transfer
function M.complete_transfer(transfer_id, success)
    local transfer = ui_state.transfer_details[transfer_id]
    if transfer then
        transfer.status = success and "completed" or "failed"
        transfer.end_time = os.time()

        -- Show notification
        local file_name = vim.fn.fnamemodify(transfer.file_path, ":t")
        local direction_icon = transfer.direction == "upload" and "↑" or "↓"

        if success then
            vim.notify(string.format("%s %s completed successfully", direction_icon, file_name), vim.log.levels.INFO)
        else
            vim.notify(string.format("%s %s failed", direction_icon, file_name), vim.log.levels.ERROR)
        end

        -- Remove from active tracking after delay
        vim.defer_fn(function()
            ui_state.transfer_details[transfer_id] = nil

            -- Hide window if no active transfers
            local active_count = 0
            for _ in pairs(ui_state.transfer_details) do
                active_count = active_count + 1
            end

            if active_count == 0 and ui_state.progress_window then
                vim.defer_fn(function()
                    M.close_progress_window()
                end, 2000) -- Hide after 2 seconds
            end
        end, 1000)
    end
end

-- Show transfer summary
function M.show_transfer_summary()
    local OptimizedCore = require("rsync.optimized_core")
    local status = OptimizedCore.get_enhanced_status()

    -- Create summary buffer
    local buf = vim.api.nvim_create_buf(false, true)
    local lines = {}

    -- Header
    table.insert(lines, "═" .. string.rep("═", 76) .. "═")
    table.insert(lines, "                    Transfer Summary")
    table.insert(lines, "═" .. string.rep("═", 76) .. "═")

    -- Recent transfers
    table.insert(lines, "")
    table.insert(lines, "Recent Transfers:")
    table.insert(lines, string.rep("─", 78))

    local recent_transfers = {}
    for i = math.max(1, #status.transfer_history - 10), #status.transfer_history do
        table.insert(recent_transfers, status.transfer_history[i])
    end

    for _, transfer in ipairs(recent_transfers) do
        local file_name = vim.fn.fnamemodify(transfer.file_path, ":t")
        local direction_icon = transfer.direction == "upload" and "↑" or "↓"
        local status_icon = transfer.status == "completed" and "✅" or "❌"

        local duration = transfer.end_time and transfer.start_time and
                       (transfer.end_time - transfer.start_time) or 0

        local line = string.format("  %s %s %-40s %ds",
            status_icon, direction_icon, file_name, duration)

        table.insert(lines, line)
    end

    -- Statistics
    table.insert(lines, "")
    table.insert(lines, "Statistics:")
    table.insert(lines, string.rep("─", 78))

    local total_transfers = #status.transfer_history
    local successful_transfers = 0
    local total_time = 0

    for _, record in ipairs(status.transfer_history) do
        if record.status == "completed" then
            successful_transfers = successful_transfers + 1
        end
        if record.end_time and record.start_time then
            total_time = total_time + (record.end_time - record.start_time)
        end
    end

    table.insert(lines, string.format("  Total Transfers:    %d", total_transfers))
    table.insert(lines, string.format("  Successful:         %d (%.1f%%)", successful_transfers,
        total_transfers > 0 and (successful_transfers / total_transfers) * 100 or 0))
    table.insert(lines, string.format("  Success Rate:       %.1f%%", status.performance_metrics.success_rate))
    table.insert(lines, string.format("  Average Speed:      %s/s",
        format_size(status.performance_metrics.average_speed)))
    table.insert(lines, string.format("  Total Time:         %ds", total_time))

    -- Network info
    table.insert(lines, "")
    table.insert(lines, "Network Information:")
    table.insert(lines, string.rep("─", 78))

    table.insert(lines, string.format("  Current Latency:    %d ms", status.network_stats.latency))
    table.insert(lines, string.format("  Max Connections:    %d", status.adaptive_params.max_connections))
    table.insert(lines, string.format("  Compression:        %s",
        status.adaptive_params.compression_enabled and "Enabled" or "Disabled"))
    table.insert(lines, string.format("  Batch Size:         %d", status.adaptive_params.batch_size))

    -- Set buffer content
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(buf, "modifiable", false)
    vim.api.nvim_buf_set_option(buf, "filetype", "text")

    -- Open in window
    vim.cmd("split")
    vim.api.nvim_win_set_buf(0, buf)
    vim.api.nvim_buf_set_name(buf, "Rsync Transfer Summary")

    -- Set up keymaps
    vim.api.nvim_buf_set_keymap(buf, "n", "q", ":close<CR>", { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", ":close<CR>", { noremap = true, silent = true })
end

-- Close progress window
function M.close_progress_window()
    if ui_state.timer then
        ui_state.timer:close()
        ui_state.timer = nil
    end

    if ui_state.progress_window and vim.api.nvim_win_is_valid(ui_state.progress_window) then
        vim.api.nvim_win_close(ui_state.progress_window, true)
        ui_state.progress_window = nil
    end

    ui_state.progress_buffer = nil
end

-- Show quick progress notification
function M.show_quick_notification(message, level)
    level = level or vim.log.levels.INFO

    -- Create notification buffer for floating window
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {message})

    -- Create floating window
    local win = vim.api.nvim_open_win(buf, false, {
        relative = "editor",
        width = 40,
        height = 1,
        col = vim.fn.winwidth(0) - 45,
        row = 5,
        style = "minimal",
        border = "single"
    })

    -- Auto-close after delay
    vim.defer_fn(function()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end, 2000)

    vim.notify(message, level)
end

return M