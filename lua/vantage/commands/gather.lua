--- The gather flow (terminal tokens `files` and `buffers`): pick several
--- files or buffers through the Picker and type their `<relpath>` references
--- into the focused Agent's input through the shared send path. References
--- are bare paths — the Tool's `format` hook owns the dialect decoration.
local Backend = require("vantage.backend")
local Config = require("vantage.config")
local Entries = require("vantage.frontend.entries")
local Picker = require("vantage.frontend.picker")
local Terminal = require("vantage.frontend.terminal")
local Util = require("vantage.util")

local M = {}

--- External file listers tried in order. All three skip `.git`, and each one's
--- output is the listing: it is not sorted, so the order is the tool's. `find`
--- is the last resort and the crudest — unlike fd and rg it reads no ignore
--- files, so a find-only machine lists what find sees.
local LISTERS = {
  { name = "fd", argv = { "fd", "--type", "f", "--type", "l", "--color", "never", "-E", ".git" } },
  { name = "rg", argv = { "rg", "--files", "--no-messages", "--color", "never", "-g", "!.git" } },
  { name = "find", argv = { "find", ".", "-type", "f", "-not", "-path", "*/.git/*" } },
}

--- The lister `setup` resolved, or nil when none is installed.
---@type { name: string, argv: string[] }?
local lister

--- Resolve the file lister from PATH: the first of fd, rg, find that is
--- installed. The resolved program is used for every later run, so installing
--- one or changing PATH takes another setup; a program that fails reports its
--- own failure instead of falling through to the next one.
function M.setup()
  lister = nil
  for _, candidate in ipairs(LISTERS) do
    if vim.fn.executable(candidate.name) == 1 then
      lister = candidate
      return
    end
  end
end

--- Whether a lister's exit code is an answer rather than a failure. `rg --files`
--- exits 1 when it found no files, which is a legitimate empty listing — a
--- project whose files are all ignored must not read as a failure. Every other
--- non-zero code is a failure (fd reports errors as 1, find as 1).
---@param name string
---@param code integer
---@return boolean
local function answered(name, code)
  return code == 0 or (name == "rg" and code == 1)
end

--- Stream the file candidates under `cwd`, the listing root and display base:
--- Neovim's global cwd, the tree the user is browsing rather than the Agent's.
--- One batch per chunk of the lister's output. The lister is the one `setup`
--- resolved; a run that fails reports it and ends, and whatever the run
--- produced before failing stays listed.
---@param cwd string
---@param emit fun(entries: vantage.picker.Entry[])
---@param done fun()
---@return fun() cancel
local function stream_files(cwd, emit, done)
  if not lister then
    Util.warn("no file lister (fd, rg, or find)")
    done()
    return function() end
  end
  local name = lister.name
  return Util.run_lines(lister.argv, { cwd = cwd }, function(lines)
    local entries = {}
    for _, line in ipairs(lines) do
      entries[#entries + 1] = Entries.file(vim.fs.normalize(vim.fs.joinpath(cwd, line)), cwd)
    end
    emit(entries)
  end, function(code)
    if not answered(name, code) then
      Util.warn(("file listing failed (%s)"):format(name))
    end
    done()
  end)
end

--- Buffer candidates: listed, normal-buftype, named, readable-on-disk
--- buffers, most recently used first (path order breaks ties), each displayed
--- relative to `cwd` (Neovim's global cwd).
---@param cwd string
---@return vantage.picker.Entry[]
local function buffer_items(cwd)
  local rows = {}
  for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    local name = info.name
    if name ~= "" and vim.bo[info.bufnr].buftype == "" and vim.fn.filereadable(name) == 1 then
      rows[#rows + 1] = {
        lastused = info.lastused or 0,
        item = Entries.buffer(info.bufnr, vim.fs.normalize(name), cwd, vim.bo[info.bufnr].modified),
      }
    end
  end
  table.sort(rows, function(a, b)
    if a.lastused ~= b.lastused then
      return a.lastused > b.lastused
    end
    return a.item.path < b.item.path
  end)
  local items = {}
  for _, row in ipairs(rows) do
    items[#items + 1] = row.item
  end
  return items
end

--- The two sources' streams: `files` runs the resolved lister (live), and
--- `buffers` reads the in-memory list in one batch.
---@type table<string, { prompt: string, stream: fun(cwd: string, emit: fun(entries: vantage.picker.Entry[]), done: fun()): (fun()?) }>
local SOURCES = {
  files = { prompt = "Files: ", stream = stream_files },
  buffers = {
    prompt = "Buffers: ",
    ---@param cwd string
    ---@param emit fun(entries: vantage.picker.Entry[])
    ---@param done fun()
    stream = function(cwd, emit, done)
      emit(buffer_items(cwd))
      done()
    end,
  },
}

--- Pick several entries from `source` and type their references into the
--- focused Agent's input.
---@param source "files"|"buffers"
local function run(source)
  Picker.pick_fancy({
    prompt = SOURCES[source].prompt,
    many = true,
    preview = Entries.preview,
    items = function(emit, done)
      -- Candidates come from the tree the user is browsing; the chosen
      -- references are still spelled against the Agent's cwd below (relative
      -- inside it, absolute outside), so the two bases are deliberately split.
      return SOURCES[source].stream(Util.cwd(), emit, done)
    end,
  }, {
    on_choices = function(chosen)
      -- The Focus is read here, at the send, not when the picker opened: the
      -- Agent whose Cwd and Tool spell these references is the one displayed
      -- when the user confirms, so a Focus that moved during the pick is the
      -- one that gets the text. A missing Focus ends the flow with nothing
      -- sent — there is no Agent to send to.
      local attachment = Terminal.attachment
      local agent, err
      if attachment then
        agent, err = attachment:focus()
      end
      if not agent then
        Util.warn(err or "no focused agent")
        return
      end
      -- Every chosen path is spelled through the Tool's dialect, joined with
      -- `setup { gather = { join = … } }`, and pasted with a trailing space so
      -- continued typing stays off the last reference. A reference the hook
      -- declines drops the whole send. No trailing newline: a pasted trailing
      -- newline shows as an empty line in the Agent's input.
      local refs = {}
      for _, item in ipairs(chosen) do
        ---@cast item vantage.picker.PathEntry
        local ref = Config.tool_reference(agent.tool, agent.cwd, item.path)
        if ref == nil then
          Util.warn("no references sent: dropped by its format hook")
          return
        end
        refs[#refs + 1] = ref
      end
      local ok, send_err = Backend.send(agent, table.concat(refs, Config.options.gather.join) .. " ")
      if not ok then
        Util.warn(send_err or "failed to send references")
      end
    end,
  })
end

--- Choose files and send their references to the focused Agent.
function M.files()
  run("files")
end

--- Choose buffers and send their references to the focused Agent.
function M.buffers()
  run("buffers")
end

return M
