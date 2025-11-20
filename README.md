# rsync.nvim

一个高效的 Neovim 插件，提供智能的文件同步功能，通过 rsync 命令实现本地与远程服务器之间的文件传输。

## ✨ 特性

- 🚀 **智能文件分组** - 根据文件类型和大小自动分组优化传输顺序
- 🔄 **自适应网络** - 根据网络状况自动调整传输参数
- 📊 **实时进度** - 提供详细的传输进度和性能统计
- 🔧 **批量处理** - 智能批处理策略，最大化传输效率
- 🎯 **精确过滤** - 支持文件包含/排除模式
- 🛡️ **错误恢复** - 智能重试机制和错误处理
- 💾 **状态持久化** - 保存传输历史和统计信息

## 📦 安装

使用你喜欢的插件管理器：

### Packer.nvim
```lua
use {
    "your-username/rsync.nvim",
    config = function()
        require("rsync").setup()
    end
}
```

### Lazy.nvim
```lua
{
    "your-username/rsync.nvim",
    config = function()
        require("rsync").setup()
    end
}
```

## 🚀 快速开始

### 1. 基本配置

在你的项目根目录创建 `.rsync.json` 文件：

```json
{
  "host": "your-server.com",
  "username": "your-username",
  "local_path": "~/your-project",
  "remote_path": "~/remote-project",
  "sync_on_save": true,
  "exclude_patterns": [
    ".git/",
    "*.tmp",
    "*.log"
  ]
}
```

### 2. 初始化插件

在你的 Neovim 配置中：

```lua
require("rsync").setup({
    -- 可选的全局配置会覆盖项目配置
    max_connections = 5,
    batch_size = 50
})
```

### 3. 基本使用

```vim
" 上传当前文件
:RsyncUpload

" 下载文件
:RsyncDownload remote-file.txt

" 同步整个项目
:RsyncSync

" 查看传输状态
:RsyncStatus
```

## 📋 命令参考

### 文件操作
- `:RsyncUpload [file...]` - 上传文件到远程服务器
- `:RsyncDownload [file...]` - 从远程服务器下载文件
- `:RsyncSyncBuffer` - 同步当前缓冲区文件

### 目录操作
- `:RsyncUploadDir [dir]` - 上传目录
- `:RsyncDownloadDir [dir]` - 下载目录

### 项目同步
- `:RsyncSync` - 同步整个项目
- `:RsyncSync` - 基于配置文件同步所有更改

### 状态和配置
- `:RsyncStatus` - 显示当前传输状态
- `:RsyncConfig [key] [value]` - 查看/设置配置
- `:RsyncTestConnection` - 测试 SSH 连接
- `:RsyncDiff [file]` - 显示本地和远程文件差异

### 管理操作
- `:RsyncCancel [task_id]` - 取消传输任务

## ⚙️ 配置选项

### 连接设置
```json
{
  "host": "server.com",              // 远程主机地址 (必需)
  "username": "user",                // 用户名 (必需)
  "port": 22,                        // SSH 端口 (默认: 22)
  "private_key_path": "~/.ssh/id_rsa", // SSH 私钥路径
  "connection_timeout": 30000        // 连接超时 (毫秒)
}
```

### 路径设置
```json
{
  "local_path": "~/project",         // 本地路径 (必需)
  "remote_path": "~/remote-project"  // 远程路径 (必需)
}
```

### 同步行为
```json
{
  "auto_sync": false,                // 自动同步
  "sync_on_save": true,              // 保存时同步
  "sync_interval": 30000             // 同步间隔 (毫秒)
}
```

### 文件过滤
```json
{
  "include_patterns": ["*.lua", "*.vim"], // 包含模式
  "exclude_patterns": [                    // 排除模式
    ".git/",
    "*.tmp",
    "*.log",
    ".DS_Store"
  ],
  "max_file_size": 10485760           // 最大文件大小 (字节)
}
```

### 性能设置
```json
{
  "max_connections": 5,              // 最大连接数
  "batch_size": 50,                  // 批处理大小
  "compression": true                // 启用压缩
}
```

### Rsync 选项
```json
{
  "rsync_options": {
    "archive": true,        // -a 归档模式
    "compress": true,       // -z 压缩传输
    "progress": true,       // --progress 显示进度
    "delete": false,        // --delete 删除多余文件
    "checksum": false,      // -c 基于校验和跳过
    "verbose": false        // -v 详细输出
  }
}
```

## 🎯 智能特性

### 文件分组策略

插件会自动将文件分组以优化传输：

1. **配置文件** (.json, .yaml, .env 等) - 最高优先级
2. **小文件** (< 1MB) - 快速传输
3. **中等文件** (1MB - 10MB) - 标准处理
4. **二进制文件** (.jpg, .pdf 等) - 特殊处理
5. **大文件** (> 10MB) - 单独处理

### 网络自适应

- **低延迟网络** (< 50ms): 增加并发数
- **高延迟网络** (> 300ms): 启用压缩，减少并发
- **高丢包率** (> 5%): 降低连接数，增加超时

### 智能重试

- **网络超时**: 指数退避重试
- **连接错误**: 延长重试间隔
- **磁盘错误**: 立即停止，不重试

## 📊 进度显示

插件提供多种进度反馈：

### 浮动进度窗口
- 实时显示传输进度
- 网络状态信息
- 性能统计数据

### 通知系统
- 传输开始/完成通知
- 错误和警告信息
- 快速进度提示

### 状态面板
- 活跃传输列表
- 传输历史记录
- 详细统计信息

## 🔧 高级用法

### Lua API

```lua
local rsync = require("rsync")

-- 上传单个文件
rsync.sync_file("path/to/file.txt", "upload", function(success, result)
    if success then
        print("文件上传成功")
    else
        print("上传失败: " .. result.message)
    end
end)

-- 批量上传文件
rsync.sync_files({"file1.txt", "file2.txt"}, "upload", callback)

-- 同步目录
rsync.sync_directory("src/", "upload", callback)

-- 获取状态
local status = rsync.get_status()
print("活跃连接: " .. status.pool_status.active_connections)
```

### 预设配置

```lua
require("rsync").setup({
    preset = "development", -- development, production, slow_network
    custom_options = {
        -- 覆盖预设选项
    }
})
```

## 🐛 故障排除

### 常见问题

1. **SSH 连接失败**
   ```bash
   # 测试 SSH 连接
   ssh -p 22 user@server.com "echo 'OK'"
   ```

2. **权限问题**
   ```bash
   # 确保私钥文件权限正确
   chmod 600 ~/.ssh/id_rsa
   ```

3. **rsync 命令未找到**
   ```bash
   # 安装 rsync
   # Ubuntu/Debian:
   sudo apt install rsync
   # CentOS/RHEL:
   sudo yum install rsync
   # macOS:
   brew install rsync
   ```

### 调试模式

```lua
-- 启用详细日志
vim.g.rsync_debug = true

-- 查看详细错误信息
:RsyncStatus
```

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

MIT License

---

**注意**: 此插件需要系统安装 `rsync` 和 `ssh` 命令。