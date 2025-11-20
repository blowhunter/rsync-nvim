编写一个neovim插件，调用linux系统中的rsync命令实现根据项目下的配置文件，实现：

1. 单个文件的上传下载
2. 多个文件的上传下载
3. 目录的上传下载
4. 保留文件权限的上传下载

整体要求：

1. 针对多文件操作或者目录操作的时候，能够预处理后统一调用rsync进行处理
2. 支持多线程或进程操作
3. 支持池化复用技术，避免多文件每个文件都去新建连接，需要关注处理效率

代码应该是使用lua语言编写，注意插件的编写符合neovim要求的规范

补充配置文件的参考格式如下：
```json
{
  "remote_path": "~/test",
  "private_key_path": "~/.ssh/id_rsa",
  "host": "8.152.204.236",
  "auto_sync": false,
  "sync_on_save": true,
  "sync_interval": 30000,
  "include_patterns": [],
  "port": 22,
  "username": "root",
  "local_path": "~/work/rust/astra.nvim",
  "max_file_size": 10485760,
  "exclude_patterns": [
    ".git/",
    "*.tmp",
    "*.log",
    ".DS_Store"
  ]
}```
