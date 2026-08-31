--- Verify every tracked Markdown file with the marksman LSP.
---
--- Run via: nvim --headless -u NONE -l scripts/verify-markdown.lua
--- Exits 0 when no Error/Warning diagnostics remain (Information/Hint are
--- reported but do not fail), 1 otherwise, and skips cleanly when marksman is
--- unavailable. Uses only Neovim (jobstart + vim.json), no Node.

local vim = vim

local function fnamemodify(s, m)
  return vim.fn.fnamemodify(s, m)
end

-- Resolve the repo root from this script's location (nvim -l sets arg[0]).
local script_path = (arg and arg[0]) and fnamemodify(arg[0], ":p") or ""
local scripts_dir = script_path ~= "" and (vim.fs.dirname(script_path) or ".") or "."
local repo_root = vim.fs.dirname(scripts_dir) or "."

local function find_marksman()
  local env = os.getenv("MARKSMAN")
  if env and env ~= "" and vim.fn.executable(env) == 1 then
    return env
  end
  if vim.fn.executable("marksman") == 1 then
    return "marksman"
  end
  local mason = vim.fs.joinpath(os.getenv("HOME") or "", ".local", "share", "nvim", "mason", "bin", "marksman")
  if vim.fn.filereadable(mason) == 1 then
    return mason
  end
  return nil
end

local marksman = find_marksman()
if not marksman then
  io.stdout:write("note: marksman not installed; skipping markdown link check\n")
  os.exit(0)
end

local files = {}
local git = vim.system({ "git", "ls-files", "*.md" }, { text = true, cwd = repo_root }):wait()
if git.code == 0 then
  for line in (git.stdout or ""):gmatch("[^\r\n]+") do
    if line:find("%S") then
      files[#files + 1] = line
    end
  end
end
if #files == 0 then
  io.stdout:write("note: no Markdown files to check\n")
  os.exit(0)
end

local diags = {}
local stderr_buf = ""
local init_ok = false

local function handle_message(msg)
  if msg.id == "1" then
    init_ok = true
  elseif msg.method == "textDocument/publishDiagnostics" then
    diags[msg.params.uri] = msg.params.diagnostics or {}
  end
end

local job = vim.fn.jobstart({ marksman, "server" }, {
  cwd = repo_root,
  on_stdout = function(_, data)
    -- Line mode: each element is one line. JSON-RPC bodies contain no literal
    -- newlines, so every JSON message is exactly one line; parse lines that are
    -- JSON objects and ignore the Content-Length header/blank separators.
    if data then
      for _, line in ipairs(data) do
        local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed:sub(1, 1) == "{" then
          local ok, msg = pcall(vim.json.decode, trimmed)
          if ok and msg ~= nil then
            handle_message(msg)
          end
        end
      end
    end
  end,
  on_stderr = function(_, data)
    if data then
      stderr_buf = stderr_buf .. table.concat(data, "\n")
    end
  end,
})

if job <= 0 then
  io.stdout:write("note: failed to start marksman; skipping markdown link check\n")
  os.exit(0)
end

local function send(payload)
  local body = vim.json.encode(payload)
  vim.fn.chansend(job, "Content-Length: " .. #body .. "\r\n\r\n" .. body)
end

send({
  jsonrpc = "2.0",
  id = "1",
  method = "initialize",
  params = {
    processId = vim.fn.getpid(),
    rootUri = "file://" .. repo_root,
    capabilities = { workspace = { workspaceFolders = true } },
    workspaceFolders = { { uri = "file://" .. repo_root, name = "vantage" } },
  },
})

if not vim.wait(10000, function()
  return init_ok
end) then
  io.stderr:write("verify-markdown: marksman did not respond to initialize\n")
  if stderr_buf ~= "" then
    io.stderr:write(stderr_buf)
  end
  vim.fn.jobstop(job)
  os.exit(2)
end

send({ jsonrpc = "2.0", method = "initialized", params = {} })
for _, f in ipairs(files) do
  local abs = vim.fs.joinpath(repo_root, f)
  local text = ""
  local fh = io.open(abs, "r")
  if fh then
    text = fh:read("*a")
    fh:close()
  end
  send({
    jsonrpc = "2.0",
    method = "textDocument/didOpen",
    params = {
      textDocument = {
        uri = "file://" .. abs,
        languageId = "markdown",
        version = 1,
        text = text,
      },
    },
  })
end

-- Give marksman time to index the folder and publish diagnostics.
vim.wait(4000, function()
  return false
end)

local failing = 0
local reported = 0
for _, f in ipairs(files) do
  local uri = "file://" .. vim.fs.joinpath(repo_root, f)
  local ds = diags[uri] or {}
  for _, d in ipairs(ds) do
    reported = reported + 1
    local line = ((d.range and d.range.start and d.range.start.line) or 0) + 1
    local sev = d.severity or 0
    local label = ({ "error", "warning", "information", "hint" })[sev + 1] or ("sev" .. tostring(sev))
    if sev <= 1 then
      failing = failing + 1
      io.stderr:write(string.format("%s:%d: [%s] %s\n", f, line, label, d.message or ""))
    else
      io.stdout:write(string.format("%s:%d: [%s] %s\n", f, line, label, d.message or ""))
    end
  end
end

vim.fn.jobstop(job)

if failing > 0 then
  if stderr_buf ~= "" then
    io.stderr:write(stderr_buf)
  end
  io.stderr:write(string.format("verify-markdown: %d error/warning diagnostic(s) across %d file(s)\n", failing, #files))
  os.exit(1)
end

local suffix = reported > 0 and string.format(" (%d info/hint)", reported) or ""
io.stdout:write(string.format("verify-markdown: %d file(s) checked, no error/warning diagnostics%s.\n", #files, suffix))
os.exit(0)
