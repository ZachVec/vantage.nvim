#!/usr/bin/env -S nvim -l

-- Test bootstrap modeled on snacks.nvim: lazy.nvim installs mini.test and
-- luassert into a stdpath isolated under .tests/, then runs every
-- tests/**/*_spec.lua file.
vim.env.LAZY_STDPATH = ".tests"

-- Prefer an existing lazy.nvim checkout so the runner works offline for the
-- bootstrap itself; fall back to lazy.nvim's official bootstrap (which is
-- also what snacks.nvim's own tests/minit.lua does).
local lazy_candidates = {
  vim.fn.fnamemodify("~/.local/share/nvim/lazy/lazy.nvim", ":p"),
  vim.fn.fnamemodify("~/.local/share/nvim/site/pack/lazy/start/lazy.nvim", ":p"),
  vim.fn.fnamemodify("~/projects/lazy.nvim", ":p"),
}
if vim.env.LAZY_PATH and vim.env.LAZY_PATH ~= "" then
  table.insert(lazy_candidates, 1, vim.env.LAZY_PATH)
end
local lazy_path
for _, path in ipairs(lazy_candidates) do
  if path and path ~= "" and vim.fn.isdirectory(path) == 1 then
    lazy_path = path
    break
  end
end

vim.env.LAZY_PATH = lazy_path
if lazy_path then
  loadfile(vim.fs.joinpath(lazy_path, "bootstrap.lua"))()
else
  load(vim.fn.system("curl -s https://raw.githubusercontent.com/folke/lazy.nvim/main/bootstrap.lua"), "bootstrap.lua")()
end

-- Setup lazy.nvim and, with --minitest, run the collected specs.
require("lazy.minit").setup({
  spec = {
    { dir = vim.uv.cwd() },
  },
})
