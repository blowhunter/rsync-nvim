# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the **blowhunter/rsync-nvim** plugin - a Neovim plugin written in Lua that provides rsync integration for file synchronization operations. The plugin wraps Linux's rsync command to enable efficient file and directory transfers with connection pooling and multi-processing capabilities.

## Core Requirements

The plugin must support:
1. Single file upload/download
2. Multiple files upload/download
3. Directory upload/download
4. Permission-preserving transfers
5. Batch processing for multi-file/directory operations
6. Multi-threading/multi-processing support
7. Connection pooling to avoid repeated connection setup

## Neovim Plugin Structure

Since this is a standard Neovim Lua plugin, follow these conventions:

- **Main entry point**: `lua/rsync/` directory structure
- **Configuration**: Project-level configuration files (format TBD)
- **Commands**: Expose Neovim user commands for rsync operations
- **API**: Provide Lua API for programmatic access

## Development Guidelines

### Lua Programming for Neovim
- Use Neovim's built-in Lua APIs (vim.fn, vim.cmd, etc.)
- Follow standard Lua module patterns
- Leverage vim.loop for async operations where appropriate

### Rsync Integration
- Use `vim.fn.system()` or `vim.fn.jobstart()` for rsync command execution
- Implement proper error handling and status reporting
- Parse rsync output for progress feedback

### Performance Considerations
- Implement connection pooling to reuse rsync connections
- Use batch processing for multiple file operations
- Consider async operations to avoid blocking Neovim UI

## File Structure (Planned)

```
lua/rsync/
├── init.lua              # Main module entry point
├── config.lua            # Configuration management
├── core.lua              # Core rsync operations
├── pool.lua              # Connection pooling logic
├── utils.lua             # Utility functions
└── commands.lua          # Neovim command definitions
```

## Testing

Since this involves system commands, testing should include:
- Unit tests for Lua modules
- Integration tests with actual rsync commands
- Mock testing for Neovim APIs

## Configuration Format

The configuration file format needs to be designed to support:
- Local/remote path mappings
- Rsync options and flags
- Connection pool settings
- Multi-threading preferences