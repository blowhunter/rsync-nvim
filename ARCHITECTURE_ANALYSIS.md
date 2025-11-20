# Rsync.nvim 架构分析与优化方案

## 当前设计问题分析

### 1. 核心架构问题

#### 1.1 连接池设计误解
**问题**: 当前设计中的"连接池"实际上是任务队列，而非真正的连接池

**分析**:
- rsync/ssh 协议本身是短连接，每次执行命令都会建立新连接
- 真正的连接复用需要使用 rsync daemon 模式或持久 SSH 连接
- 当前设计无法避免重复连接建立的开销

**影响**: 性能提升有限，特别是在高延迟网络环境中

#### 1.2 批处理策略缺陷
**问题**: 批处理设计过于简单，没有考虑文件特性和网络条件

**分析**:
- 所有文件统一批处理，忽略了文件大小差异
- 使用临时文件增加磁盘I/O开销
- 缺乏动态批处理大小调整

**影响**: 在某些场景下可能比单个文件传输更慢

### 2. 性能问题

#### 2.1 并发控制不当
**问题**: 固定的最大连接数限制，无法适应不同网络环境

**分析**:
- 没有根据网络延迟动态调整并发数
- 大文件和小文件使用相同的并发策略
- 缺乏带宽限制机制

#### 2.2 文件分组策略缺失
**问题**: 缺乏智能的文件分组和排序策略

**分析**:
- 没有按文件大小、类型进行分组
- 重要文件可能排在后面处理
- 缺乏依赖关系处理

### 3. 可靠性问题

#### 3.1 错误处理不完善
**问题**: 错误处理和恢复机制不足

**分析**:
- 网络中断时缺乏自动重试
- 部分失败时无法确定具体失败文件
- 没有断点续传支持

#### 3.2 状态管理缺失
**问题**: 缺乏持久化的状态管理

**分析**:
- 插件重启后状态丢失
- 无法查询历史传输记录
- 缺乏传输统计信息

### 4. 用户体验问题

#### 4.1 反馈不足
**问题**: 异步操作缺乏足够的用户反馈

**分析**:
- 缺乏进度显示和速度统计
- 用户无法了解传输状态
- 错误信息不够详细

#### 4.2 配置复杂性
**问题**: 配置选项过多，用户体验复杂

**分析**:
- 需要用户配置的项目过多
- 缺乏配置向导和验证
- 默认配置可能不适合所有场景

## 优化方案设计

### 1. 重新设计传输策略

#### 1.1 智能文件分组
```lua
-- 按文件大小和类型分组
local function group_files_by_strategy(files)
    local groups = {
        small_files = {},    -- < 1MB
        medium_files = {},   -- 1MB - 10MB
        large_files = {},    -- > 10MB
        config_files = {},   -- 配置文件优先
        binary_files = {}    -- 二进制文件
    }

    for _, file in ipairs(files) do
        local size = get_file_size(file)
        local ext = get_file_extension(file)

        if is_config_file(file) then
            table.insert(groups.config_files, file)
        elseif size < 1024 * 1024 then
            table.insert(groups.small_files, file)
        elseif size < 10 * 1024 * 1024 then
            table.insert(groups.medium_files, file)
        else
            table.insert(groups.large_files, file)
        end
    end

    return groups
end
```

#### 1.2 动态并发控制
```lua
-- 根据网络条件动态调整并发数
local function calculate_optimal_concurrency()
    local network_latency = measure_network_latency()
    local bandwidth = measure_available_bandwidth()

    if network_latency < 50 and bandwidth > 10 then -- 高速网络
        return math.min(10, #pending_files)
    elseif network_latency < 200 then -- 中速网络
        return math.min(5, #pending_files)
    else -- 低速网络
        return math.min(2, #pending_files)
    end
end
```

### 2. 增强错误处理和重试机制

#### 2.1 智能重试策略
```lua
local function should_retry(attempt, error_type, file_size)
    -- 根据错误类型和文件大小决定是否重试
    if error_type == "network_timeout" and attempt < 3 then
        return true, 2000 * attempt -- 指数退避
    elseif error_type == "connection_failed" and attempt < 5 then
        return true, 5000 * attempt
    elseif error_type == "disk_full" then
        return false -- 不重试磁盘满错误
    end

    return attempt < 2, 1000
end
```

#### 2.2 增量同步优化
```lua
-- 使用 rsync --checksum 进行增量检查
local function intelligent_sync(files)
    -- 先进行快速检查
    local changed_files = check_file_changes(files)

    if #changed_files < #files then
        local skipped = #files - #changed_files
        vim.notify(string.format("跳过 %d 个未更改的文件", skipped), vim.log.levels.INFO)
    end

    -- 只传输变化的文件
    return transfer_files(changed_files)
end
```

### 3. 改进用户界面和反馈

#### 3.1 实时进度显示
```lua
-- 创建浮动窗口显示传输进度
local function create_progress_window()
    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_floating_win(buf, false, {
        relative = "editor",
        width = 60,
        height = 10,
        border = "rounded"
    })

    -- 定期更新进度
    local timer = vim.loop.new_timer()
    timer:start(0, 500, vim.schedule_wrap(function()
        update_progress_display(buf)
    end))

    return buf, win, timer
end
```

#### 3.2 传输统计和分析
```lua
local function collect_transfer_stats()
    return {
        total_files = total_file_count,
        completed_files = completed_count,
        failed_files = failed_count,
        total_bytes = total_size,
        transferred_bytes = transferred_size,
        current_speed = calculate_speed(),
        estimated_time_remaining = calculate_eta(),
        compression_ratio = get_compression_ratio()
    }
end
```

### 4. 配置优化和简化

#### 4.1 配置向导
```lua
-- 交互式配置设置
local function setup_interactive_config()
    vim.ui.input({prompt = "远程主机地址: "}, function(host)
        vim.ui.input({prompt = "用户名: "}, function(username)
            vim.ui.input({prompt = "本地路径: "}, function(local_path)
                -- 测试连接
                test_connection_and_save(host, username, local_path)
            end)
        end)
    end)
end
```

#### 4.2 预设配置模板
```lua
local config_presets = {
    development = {
        max_connections = 3,
        batch_size = 20,
        sync_interval = 5000,
        auto_sync = true
    },
    production = {
        max_connections = 5,
        batch_size = 100,
        sync_interval = 60000,
        auto_sync = false
    },
    slow_network = {
        max_connections = 1,
        batch_size = 10,
        sync_interval = 30000,
        compression = true
    }
}
```

### 5. 性能监控和优化

#### 5.1 网络状况自适应
```lua
local function adapt_to_network_conditions()
    local stats = get_network_stats()

    if stats.packet_loss > 0.05 then -- 高丢包率
        reduce_concurrency()
        increase_timeout()
        enable_compression()
    elseif stats.latency > 500 then -- 高延迟
        enable_compression()
        increase_batch_size()
    end
end
```

## 实施优先级

### 高优先级 (立即实施)
1. 修复批处理逻辑，移除不必要的临时文件
2. 增加基本的错误重试机制
3. 添加进度显示和用户反馈
4. 简化配置流程

### 中优先级 (下一版本)
1. 实现智能文件分组
2. 添加网络状况自适应
3. 增强状态管理和持久化
4. 完善统计和分析功能

### 低优先级 (未来版本)
1. 实现断点续传
2. 添加带宽限制功能
3. 实现更复杂的传输策略
4. 添加传输历史记录

## 总结

当前设计在基本功能上是可行的，但在性能、可靠性和用户体验方面还有很大改进空间。通过实施上述优化方案，可以显著提升插件的实用性和用户满意度。

重点应该放在：
1. 修复核心传输逻辑问题
2. 增强错误处理和恢复能力
3. 改进用户界面和反馈
4. 简化配置和使用流程