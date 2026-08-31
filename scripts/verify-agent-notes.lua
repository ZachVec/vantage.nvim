--- Verify the Agent Note tree and file formats under .agents/notes/.
---
--- Pure Lua (LuaJIT-compatible); run via:
---   nvim --headless -u NONE -l scripts/verify-agent-notes.lua
--- Exits 0 when every note conforms, 1 on any structure or format violation.
--- The rules it enforces live in .agents/notes/README.md.

local fnamemodify = vim.fn.fnamemodify

-- Resolve the notes root from this script's location so the gate is
-- cwd-independent (nvim -l sets arg[0] to the script path).
local script_path = (arg and arg[0]) and fnamemodify(arg[0], ":p") or ""
local scripts_dir = script_path ~= "" and (vim.fs.dirname(script_path) or ".") or "."
local repo_root = vim.fs.dirname(scripts_dir) or "."
local NOTES_ROOT = vim.fs.joinpath(repo_root, ".agents", "notes")

local LIFECYCLES = { "proposed", "implemented", "rejected" }
local ARCHIVE = "archived"
local CLASSES = { "feature", "bug-fix", "simplification", "architecture", "process", "testing" }

local LIFECYCLE_SET, CLASS_SET = {}, {}
for _, name in ipairs(LIFECYCLES) do
  LIFECYCLE_SET[name] = true
end
for _, name in ipairs(CLASSES) do
  CLASS_SET[name] = true
end

-- Files allowed to sit directly at a lifecycle root or the notes root.
local ROOT_ALLOWLIST = { ["AGENTS.md"] = true, ["CLAUDE.md"] = true }

-- Status-line grammar per lifecycle folder; the rejected reason is the one
-- status with content (see .agents/notes/README.md § The header block). The
-- rejected dash is matched as a literal (em-dash or hyphen) — NOT inside a
-- character class, which in Lua matches single bytes and cannot span the
-- 3-byte em-dash.
local STATUS = {
  proposed = "^Status: proposed$",
  implemented = "^Status: implemented$",
}

local function status_ok(lifecycle, line)
  if lifecycle == "rejected" then
    return line:match("^Status: rejected — .+$") ~= nil or line:match("^Status: rejected - .+$") ~= nil
  end
  local pat = STATUS[lifecycle]
  return pat ~= nil and line:match(pat) ~= nil
end

-- Required `##` headings per lifecycle, beyond the universal `## Problem` opener.
local REQUIRED = {
  proposed = { "## Proposal", "## Acceptance criteria", "## Risks" },
  implemented = { "## Decision", "## Consequences" },
  rejected = { "## Proposal" },
}

-- Proposal-era headings banned in `implemented/` (they are spec-speak; an
-- implemented note states what is).
local BANNED_IMPLEMENTED = { "## Proposal", "## Plan", "## Migration plan", "## Acceptance criteria" }

local notes = {}
local errors = {}

local function fail(msg)
  errors[#errors + 1] = msg
end

--- Sorted { name, type } entries of a directory; {} when it does not exist.
local function entries(path)
  local list = {}
  local ok, it = pcall(vim.fs.dir, path)
  if not ok or it == nil then
    return list
  end
  for name, ftype in it do
    list[#list + 1] = { name = name, type = ftype }
  end
  table.sort(list, function(a, b)
    return a.name < b.name
  end)
  return list
end

local function filename_ok(name)
  return name:match("^%d%d%d%d%-%d%d%-%d%d%-.+%.md$") ~= nil
end

-- ---------------------------------------------------------------------------
-- Tree structure
-- ---------------------------------------------------------------------------

-- The top-level folder set is closed: an unknown directory would otherwise
-- hold notes invisible to the walk below.
for _, e in ipairs(entries(NOTES_ROOT)) do
  if e.name == "INDEX.md" then
    fail("structure: INDEX.md — centralized Agent Note indexes are forbidden; browse the lifecycle/class tree")
  elseif e.type == "directory" and not LIFECYCLE_SET[e.name] and e.name ~= ARCHIVE then
    fail(
      string.format(
        "structure: %s/ — unknown top-level folder (allowed: proposed, implemented, rejected, plus archived/)",
        e.name
      )
    )
  end
end

-- Active lifecycles: {lifecycle}/{class}/yyyy-mm-dd-topic.md.
for _, lifecycle in ipairs(LIFECYCLES) do
  local lc_path = vim.fs.joinpath(NOTES_ROOT, lifecycle)
  for _, cls in ipairs(entries(lc_path)) do
    if cls.type == "directory" then
      if not CLASS_SET[cls.name] then
        fail(
          string.format(
            "structure: %s/%s/ — unknown class folder (allowed: %s)",
            lifecycle,
            cls.name,
            table.concat(CLASSES, ", ")
          )
        )
      end
      for _, f in ipairs(entries(vim.fs.joinpath(lc_path, cls.name))) do
        if f.type == "file" then
          if not filename_ok(f.name) then
            fail(
              string.format("structure: %s/%s/%s — filename must be yyyy-mm-dd-topic.md", lifecycle, cls.name, f.name)
            )
          else
            notes[#notes + 1] = {
              lifecycle = lifecycle,
              rel = string.format("%s/%s/%s", lifecycle, cls.name, f.name),
              date = f.name:sub(1, 10),
              path = vim.fs.joinpath(lc_path, cls.name, f.name),
            }
          end
        end
      end
    elseif cls.type == "file" and not ROOT_ALLOWLIST[cls.name] then
      fail(string.format("structure: %s/%s — only AGENTS.md may sit at a lifecycle root", lifecycle, cls.name))
    end
  end
end

-- Archive: archived/{class}/yyyy-mm-dd-topic.md (no lifecycle segment).
do
  local arc_path = vim.fs.joinpath(NOTES_ROOT, ARCHIVE)
  for _, cls in ipairs(entries(arc_path)) do
    if cls.type == "directory" then
      if not CLASS_SET[cls.name] then
        fail(
          string.format(
            "structure: archived/%s/ — unknown class folder (allowed: %s)",
            cls.name,
            table.concat(CLASSES, ", ")
          )
        )
      end
      for _, f in ipairs(entries(vim.fs.joinpath(arc_path, cls.name))) do
        if f.type == "file" then
          if not filename_ok(f.name) then
            fail(string.format("structure: archived/%s/%s — filename must be yyyy-mm-dd-topic.md", cls.name, f.name))
          else
            notes[#notes + 1] = {
              lifecycle = "implemented",
              archived = true,
              rel = string.format("archived/%s/%s", cls.name, f.name),
              date = f.name:sub(1, 10),
              path = vim.fs.joinpath(arc_path, cls.name, f.name),
            }
          end
        end
      end
    elseif cls.type == "file" and not ROOT_ALLOWLIST[cls.name] then
      fail(string.format("structure: archived/%s — only AGENTS.md may sit at the archive root", cls.name))
    end
  end
end

-- ---------------------------------------------------------------------------
-- File format
-- ---------------------------------------------------------------------------

--- Lines with fenced code blocks removed, so format tokens inside examples are
--- not mistaken for document structure.
local function prose_lines(lines)
  local out = {}
  local in_fence = false
  for _, l in ipairs(lines) do
    if l:find("^```") then
      in_fence = not in_fence
    elseif not in_fence then
      out[#out + 1] = l
    end
  end
  return out
end

local function is_banned_implemented(h2)
  for _, prefix in ipairs(BANNED_IMPLEMENTED) do
    if h2 == prefix then
      return true
    end
    if h2:sub(1, #prefix) == prefix then
      local next_char = h2:sub(#prefix + 1, #prefix + 1)
      if next_char == " " or next_char == "\t" or next_char == ":" then
        return true
      end
    end
  end
  return false
end

for _, note in ipairs(notes) do
  local lines = vim.fn.readfile(note.path)
  local nfail = function(msg)
    fail(string.format("format: %s — %s", note.rel, msg))
  end

  if not (lines[1] or ""):match("^# Agent Note: %S") then
    nfail("line 1 must be `# Agent Note: <title>`")
  end
  if lines[2] ~= "" then
    nfail("line 2 must be blank")
  end
  if note.archived then
    if (lines[3] or "") ~= "Status: implemented" then
      nfail("archived note line 3 must be `Status: implemented`")
    end
  else
    if not status_ok(note.lifecycle, lines[3] or "") then
      nfail(string.format("line 3 must match the %s status grammar", note.lifecycle))
    end
  end
  if lines[4] ~= "" then
    nfail("line 4 must be blank")
  end

  local prose = prose_lines(lines)

  -- The line-3 `Status:` line must be the only one in the file.
  local status_count = 0
  for _, l in ipairs(prose) do
    if l:find("^Status:") then
      status_count = status_count + 1
    end
  end
  if status_count ~= 1 then
    nfail("the line-3 `Status:` line must be the only one in the file")
  end

  if note.archived then
    local has_archived = false
    for _, l in ipairs(prose) do
      if l:match("^Archived: %d%d%d%d%-%d%d%-%d%d$") then
        has_archived = true
      end
    end
    if not has_archived then
      nfail("missing `Archived: YYYY-MM-DD` line (immediately below `Status: implemented`)")
    end
    -- Archived notes are frozen as-sealed; the active body format is not re-checked.
  else
    local h2s = {}
    for _, l in ipairs(prose) do
      if l:find("^## ") then
        h2s[#h2s + 1] = l:gsub("%s+$", "")
      end
    end

    if h2s[1] ~= "## Problem" then
      nfail(
        string.format("the first section must be `## Problem` (got %s)", h2s[1] and ("`" .. h2s[1] .. "`") or "<none>")
      )
    end
    for _, req in ipairs(REQUIRED[note.lifecycle] or {}) do
      local found = false
      for _, h in ipairs(h2s) do
        if h == req then
          found = true
        end
      end
      if not found then
        nfail(string.format("missing the required `%s` section", req))
      end
    end
    if note.lifecycle == "implemented" then
      for _, h in ipairs(h2s) do
        if is_banned_implemented(h) then
          nfail(string.format("`%s` is a proposal-era heading; an implemented Agent Note states what is", h))
        end
      end
    end

    local has_alternatives = false
    for _, h in ipairs(h2s) do
      if h == "## Alternatives considered" then
        has_alternatives = true
      end
    end
    if not has_alternatives then
      nfail("missing `## Alternatives considered` (each genuine alternative and why it lost)")
    end
  end
end

-- ---------------------------------------------------------------------------
-- Report
-- ---------------------------------------------------------------------------

if #errors == 0 then
  io.stdout:write(
    string.format("verify-agent-notes: %d Agent Note(s) checked, all conform to .agents/notes/README.md.\n", #notes)
  )
  os.exit(0)
end

io.stderr:write("verify-agent-notes: violations found:\n")
for _, e in ipairs(errors) do
  io.stderr:write("  " .. e .. "\n")
end
os.exit(1)
