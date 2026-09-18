--- Picker frontend facade: resolve the configured implementation and own the
--- capability/command negotiation shared by every pick.

---@class vantage.picker.Entry One selectable thing a pick offers: the line the
--- implementation renders (`text`) and the flow's own name for it (`kind`).
--- The flow owns every other field; an implementation reads `text`, and the
--- pick's own `preview` function — when the flow supplied one — turns the
--- highlighted entry into preview lines. An implementation never writes to an
--- entry.
---@field text string the line the implementation renders
---@field kind string flow-owned kind, read by the flow's own callbacks

--- A pick's item stream, written by the flow and started by the implementation.
--- `emit` appends a batch of entries as they are produced; `done` ends the run
--- (success or failure). The optional return stops a run that is still going —
--- the picker closed, or a command restarted it. A failed read is the flow's
--- own business: its source reports the reason and ends.
---@alias vantage.picker.Source fun(emit: fun(entries: vantage.picker.Entry[]), done: fun()): (fun()?)

---@class vantage.PickSpec The selection contract passed to a picker
--- implementation. The flow owns the prompt, the item stream, and the two
--- per-pick rendering requests:
---
--- `many` is how many entries the flow acts on. The flow asks for several and
--- an implementation that can only confirm one answers `on_choices` with a
--- one-element list, so a command never branches on its picker's engine.
---
--- `preview`, when present, is the standard preview for the pick: an
--- implementation that can show a pane shows one, calls the function only for
--- the highlighted entry, and keeps the pane with nothing in it for an entry
--- the function answers nil for. Without it there is no preview pane.
---@field prompt string
---@field many boolean
---@field preview? fun(entry: vantage.picker.Entry): string[]?
---@field items vantage.picker.Source

---@class vantage.PickerCommandCtx
---@field item vantage.picker.Entry? the highlighted entry, when there is one
---@field items vantage.picker.Entry[]

---@class vantage.PickerCommand A keymap-shaped picker command:
--- `{ lhs, rhs, desc? }`. `rhs` receives the neutral context and returns true
--- when the item list may have changed, which restarts the pick's item stream.
---@field [1] string lhs
---@field [2] fun(ctx: vantage.PickerCommandCtx): boolean
---@field desc? string

---@class vantage.PickOpts
---@field on_choices fun(entries: vantage.picker.Entry[]) at least one entry
---@field commands? vantage.PickerCommand[]

---@class vantage.NaiveOpts Options for the plain-select form (`pick_naive`),
--- mirroring `vim.ui.select`'s opts.
---@field prompt? string
---@field format_item? fun(item: any): string

---@class vantage.PickerCapabilities
---@field command boolean

---@class vantage.PickerImpl A selection-UI implementation (native | fzf-lua |
--- snacks) rendering every Vantage selection on its own engine. The command
--- flows write a `PickSpec` per flow; the implementations stay
--- presentation-only and depend on nothing but their engine.
---
--- An implementation owns what its own close does: it leaves the window the
--- pick was invoked from current when the picker closes, with that window's
--- mode intact, and compensates for its own teardown whenever its engine
--- loses either. A flow therefore never restores a window or a mode.
--- `native` delegates this, like everything else, to the global
--- `vim.ui.select`.
---
--- `pick_fancy` renders a streaming pick: it starts `spec.items`, maps every
--- emitted batch into its engine as it arrives, and maps `done` to its
--- engine's end of input. It honors `spec.many` and `spec.preview` as far as
--- its engine can, and calls the cancel function a source returned when the
--- picker closes or a command restarts the run. `pick_naive` renders a static
--- list through the engine's own plain select, so a flow never mixes renderer
--- families.
---@field requires? string optional runtime module dependency
---@field capabilities vantage.PickerCapabilities
---@field pick_fancy fun(spec: vantage.PickSpec, opts: vantage.PickOpts)
---@field pick_naive fun(items: any[], opts: vantage.NaiveOpts, on_choice: fun(item: any?, index?: integer))

local Config = require("vantage.config")

local M = {}

--- User-facing name -> module path. A whitelist, so a raw user string is never
--- `require`d.
local REGISTRY = {
  native = "vantage.frontend.picker.native",
  ["fzf-lua"] = "vantage.frontend.picker.fzf_lua",
  snacks = "vantage.frontend.picker.snacks",
}

---@type vantage.PickerImpl?
local resolved

--- Resolve the configured Picker. Called by the composition root before any
--- runtime side effects; invalid configuration is a setup error.
function M.setup()
  resolved = nil
  local name = Config.options.picker
  local mod = REGISTRY[name]
  if not mod then
    error(("vantage: unknown picker '%s'"):format(tostring(name)), 0)
  end
  local ok, impl = pcall(require, mod)
  if not ok then
    error(("vantage: picker '%s' unavailable (%s)"):format(name, tostring(impl)), 0)
  end
  if
    type(impl.capabilities) ~= "table"
    or type(impl.capabilities.command) ~= "boolean"
    or type(impl.pick_fancy) ~= "function"
    or type(impl.pick_naive) ~= "function"
  then
    error(("vantage: picker '%s' does not implement vantage.PickerImpl"):format(name), 0)
  end
  if impl.requires then
    local dep_ok, dep_err = pcall(require, impl.requires)
    if not dep_ok then
      error(("vantage: picker '%s' requires '%s' (%s)"):format(name, impl.requires, tostring(dep_err)), 0)
    end
  end
  resolved = impl
end

--- The resolved Picker implementation. Internal to this module.
---@return vantage.PickerImpl
local function get()
  if not resolved then
    error("vantage: picker not initialized; call require('vantage').setup() first", 0)
  end
  return resolved
end

--- Test/initialization helper: forget the resolved Picker.
function M.reset()
  resolved = nil
end

--- The resolved Picker's static capability table.
---@return vantage.PickerCapabilities
function M.capabilities()
  return get().capabilities
end

--- Validate and normalize flow commands before handing them to a renderer.
---@param commands? vantage.PickerCommand[]
---@return vantage.PickerCommand[]?
local function normalize_commands(commands)
  if not commands or #commands == 0 then
    return nil
  end
  local seen = {}
  for index, command in ipairs(commands) do
    local lhs, rhs = command[1], command[2]
    if type(lhs) ~= "string" or lhs == "" then
      error(("vantage: picker command %d has no lhs"):format(index), 0)
    end
    if type(rhs) ~= "function" then
      error(("vantage: picker command '%s' rhs must be a function"):format(lhs), 0)
    end
    if seen[lhs] then
      error(("vantage: duplicate picker command lhs '%s'"):format(lhs), 0)
    end
    seen[lhs] = true
  end
  return commands
end

--- Render a streaming pick through the configured implementation.
---@param spec vantage.PickSpec
---@param opts vantage.PickOpts
function M.pick_fancy(spec, opts)
  local impl = get()
  if type(opts.on_choices) ~= "function" then
    error("vantage: picker opts.on_choices must be a function", 0)
  end
  local commands = normalize_commands(opts.commands)
  if commands and not impl.capabilities.command then
    commands = nil
  end
  impl.pick_fancy(spec, {
    on_choices = opts.on_choices,
    commands = commands,
  })
end

--- Render a plain selection through the configured implementation.
---@param items any[]
---@param opts vantage.NaiveOpts
---@param on_choice fun(item: any?, index?: integer)
function M.pick_naive(items, opts, on_choice)
  return get().pick_naive(items, opts, on_choice)
end

return M
