-- Health check entry point for rsync-nvim
-- This file is called by :checkhealth rsync

-- Load the actual health check module from rsync.health
local M = require("rsync.health")

-- Export the check function for Neovim's health system
return M.check