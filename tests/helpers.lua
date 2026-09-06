--- Shared helpers for Vantage specs.
local M = {}

--- Drop every loaded Vantage module so each spec starts from fresh module
--- state (defaults, registries, fakes). Other specs' loaded modules are the
--- only shared process state; Neovim-side side effects (autocmd groups,
--- user commands) are re-registered idempotently by the modules themselves.
function M.reload_vantage()
  for name in pairs(package.loaded) do
    if name == "vantage" or name:find("^vantage%.") == 1 then
      package.loaded[name] = nil
    end
  end
end

--- Create a real scratch buffer with `lines`, optionally named `name`.
---@param lines string|string[]
---@param name? string
---@return integer
function M.buffer(lines, name)
  lines = type(lines) == "string" and vim.split(lines, "\n", { plain = true }) or lines
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  if name and name ~= "" then
    vim.api.nvim_buf_set_name(buf, name)
  end
  return buf
end

--- Wipe a test buffer.
---@param buf integer
function M.wipe(buf)
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
end

return M
