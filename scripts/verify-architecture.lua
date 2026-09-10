--- Verify the shipped module dependency directions under lua/vantage/.
---
--- Pure Lua (LuaJIT-compatible); run via:
---   nvim --headless -u NONE -l scripts/verify-architecture.lua
--- Exits 0 when every module-level `require("vantage...")` follows the
--- documented layering, 1 on any reverse dependency.

local fnamemodify = vim.fn.fnamemodify
local script_path = (arg and arg[0]) and fnamemodify(arg[0], ":p") or ""
local scripts_dir = script_path ~= "" and (vim.fs.dirname(script_path) or ".") or "."
local repo_root = vim.fs.dirname(scripts_dir) or "."
local source_root = vim.fs.joinpath(repo_root, "lua", "vantage")

--- Layer for a source file relative to lua/vantage.
---@param path string
---@return string
local function source_layer(path)
  local rel = path:sub(#source_root + 2)
  if rel == "init.lua" then
    return "composition"
  elseif rel == "health.lua" then
    return "health"
  elseif rel == "config.lua" or rel == "util.lua" then
    return "shared"
  elseif rel:match("^commands/") then
    return "commands"
  elseif rel:match("^frontend/") then
    return "frontend"
  elseif rel:match("^backend/") then
    return "backend"
  end
  return "shared"
end

--- Layer for a required Vantage module.
---@param module string
---@return string
local function module_layer(module)
  if module == "vantage" or module == "vantage.init" then
    return "composition"
  elseif module == "vantage.health" then
    return "health"
  elseif module == "vantage.config" or module == "vantage.util" then
    return "shared"
  elseif module:match("^vantage%.commands") then
    return "commands"
  elseif module:match("^vantage%.frontend") then
    return "frontend"
  elseif module:match("^vantage%.backend") then
    return "backend"
  end
  return "shared"
end

local ALLOWED = {
  composition = { composition = true, commands = true, frontend = true, backend = true, health = true, shared = true },
  commands = { commands = true, frontend = true, backend = true, health = true, shared = true },
  frontend = { frontend = true, backend = true, shared = true },
  backend = { backend = true, shared = true },
  health = { backend = true, frontend = true, shared = true },
  shared = { shared = true },
}

local errors = {}
local checked = 0

local files = vim.fn.glob(source_root .. "/**/*.lua", false, true)
table.sort(files)

for _, path in ipairs(files) do
  checked = checked + 1
  local source = source_layer(path)
  local rel = path:sub(#repo_root + 2)
  for _, line in ipairs(vim.fn.readfile(path)) do
    local trimmed = vim.trim(line)
    if trimmed:sub(1, 2) ~= "--" and not trimmed:find("error%s*%(") then
      local modules = {}
      for module in line:gmatch('require%s*%(%s*"([^"]+)"%s*%)') do
        modules[#modules + 1] = module
      end
      for module in line:gmatch("require%s*%(%s*'([^']+)'%s*%)") do
        modules[#modules + 1] = module
      end
      for _, module in ipairs(modules) do
        if module == "vantage" or module:match("^vantage%.") then
          local target = module_layer(module)
          if not ALLOWED[source][target] then
            errors[#errors + 1] = ("%s: %s must not require %s"):format(rel, source, module)
          end
        end
      end
    end
  end
end

if #errors > 0 then
  for _, err in ipairs(errors) do
    io.stderr:write("verify-architecture: " .. err .. "\n")
  end
  vim.cmd("cquit 1")
end

print(("verify-architecture: %d file(s) checked, no reverse dependencies."):format(checked))
