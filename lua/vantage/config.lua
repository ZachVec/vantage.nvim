--- Configuration and shared types for Vantage.

---@class vantage.Tool A launch command (name -> cmd array).
---@field cmd string[]

---@class vantage.Agent A running coding-agent process.
---@field group string
---@field target string tmux window id (@N)
---@field cmd string
---@field cwd string
---@field name string
---@field state? string

---@class vantage.Win Terminal window options.
---@field layout string float | left | top | bottom | right
---@field float table
---@field split table
---@field keys table[]

---@class vantage.Config
---@field backend string
---@field socket string
---@field cli { tools: table<string, vantage.Tool>, win: vantage.Win }

local M = {}

---@type vantage.Config
local defaults = {
  --- Pluggable backend driver name (currently only "tmux").
  backend = "tmux",
  --- Private tmux socket name, isolating Vantage from the daily tmux server.
  socket = "vantage",
  cli = {
    --- Launch commands offered when creating an Agent (name -> cmd array).
    --- Empty by default: provide your own; nothing is built in or validated.
    --- Example:
    ---   tools = {
    ---     claude = { cmd = { "claude" } },
    ---     codex  = { cmd = { "codex" } },
    ---   },
    tools = {},
    --- The persistent :terminal window that is the tmux client.
    win = {
      --- float | left | top | bottom | right
      layout = "float",
      --- border: "none" (or false) hides it; also "single"|"double"|"rounded"|"solid"
      float = { width = 0.9, height = 0.9, border = "rounded" },
      split = { width = 80, height = 20 },
      --- Buffer-local keymaps for the terminal buffer (filetype
      --- `vantage_terminal`). Empty by default — add your own. Each entry is a
      --- 4-tuple { lhs, rhs, mode = "n", desc }; `rhs` is passed verbatim to
      --- vim.keymap.set (a key sequence / <cmd> RHS or a Lua function).
      ---
      --- Example:
      ---   keys = {
      ---     { "<c-q>", "<cmd>Vantage toggle<CR>", mode = "t", desc = "toggle the terminal" },
      ---     { "q", "<cmd>Vantage toggle<CR>", mode = "n", desc = "toggle the terminal" },
      ---     { "<c-s>", function() vim.cmd("stopinsert") end, mode = "t", desc = "enter normal mode" },
      ---   },
      keys = {},
    },
  },
}

---@type vantage.Config
M.options = vim.deepcopy(defaults)

---@param opts? vantage.Config
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

  pcall(vim.api.nvim_create_user_command, "Vantage", function(args)
    require("vantage.commands").run(args)
  end, {
    nargs = "*",
    complete = function(arglead, cmdline)
      return require("vantage.commands").complete(arglead, cmdline)
    end,
    desc = "Vantage coding-agent manager",
  })
end

return M
