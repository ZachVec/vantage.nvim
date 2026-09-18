---@module 'luassert'

local Helpers = require("helpers")

describe("vantage.frontend.picker.fzf_lua", function()
  local Fzf
  local captured
  local items

  --- A source that emits its list at once.
  ---@param list vantage.picker.Entry[]
  ---@return vantage.picker.Source
  local function source(list)
    return function(emit, done)
      emit(list)
      done()
    end
  end

  --- The lines the captured contents function writes, with the end of input as
  --- a visible marker.
  ---@return string[]
  local function written()
    local lines = {}
    captured.contents(function(line)
      lines[#lines + 1] = line == nil and "<end>" or line
    end)
    return lines
  end

  setup(function()
    Helpers.reload_vantage()
    items = {
      { text = "first" },
      { text = "second" },
    }
    package.loaded["fzf-lua"] = {
      fzf_exec = function(contents, opts)
        captured = { contents = contents, opts = opts }
      end,
    }
    Fzf = require("vantage.frontend.picker.fzf_lua")
  end)

  teardown(function()
    Helpers.reload_vantage()
  end)

  it("writes one prefixed line per entry and ends the input", function()
    Fzf.pick_fancy({ prompt = "pick", many = false, items = source(items) }, { on_choices = function() end })

    assert.are.same({ "1. first", "2. second", "<end>" }, written())
    assert.are.equal("2..", captured.opts.fzf_opts["--with-nth"])
    assert.is_nil(captured.opts.fzf_opts["--nth"])
  end)

  it("maps returned lines back to their entries and answers with every choice", function()
    local chosen
    Fzf.pick_fancy({ prompt = "pick", many = true, items = source(items) }, {
      on_choices = function(rows)
        chosen = rows
      end,
    })
    written()

    assert.is_true(captured.opts.fzf_opts["--multi"])
    captured.opts.actions.default({ "2. second", "1. first" })
    vim.wait(500, function()
      return chosen ~= nil
    end)

    assert.are.equal(2, #chosen)
    assert.are.equal("second", chosen[1].text)
    assert.are.equal("first", chosen[2].text)
  end)

  it("asks for no marking when the flow acts on one entry", function()
    Fzf.pick_fancy({ prompt = "pick", many = false, items = source(items) }, { on_choices = function() end })

    assert.is_nil(captured.opts.fzf_opts["--multi"])
  end)

  it("previews the highlighted entry only when the flow asked for a preview", function()
    Fzf.pick_fancy({
      prompt = "pick",
      many = false,
      preview = function(entry)
        return entry.text == "second" and { "two" } or nil
      end,
      items = source(items),
    }, { on_choices = function() end })
    written()

    assert.are.equal("two", captured.opts.preview({ "2. second" }))
    -- A nil answer keeps the pane, empty.
    assert.are.equal("", captured.opts.preview({ "1. first" }))
  end)

  it("shows no preview pane without a preview function", function()
    Fzf.pick_fancy({ prompt = "pick", many = false, items = source(items) }, { on_choices = function() end })

    assert.is_nil(captured.opts.preview)
  end)

  it("starts a fresh run after a command that changed the list, and re-emits otherwise", function()
    local runs = 0
    Fzf.pick_fancy({
      prompt = "pick",
      many = false,
      items = function(emit, done)
        runs = runs + 1
        emit(items)
        done()
      end,
    }, {
      on_choices = function() end,
      commands = {
        {
          "<C-x>",
          function()
            return true
          end,
        },
        {
          "<C-y>",
          function()
            return false
          end,
        },
      },
    })
    written()
    assert.are.equal(1, runs)

    captured.opts.actions["ctrl-x"].fn({ "1. first" })
    written()
    assert.are.equal(2, runs)

    captured.opts.actions["ctrl-y"].fn({ "1. first" })
    assert.are.same({ "1. first", "2. second", "<end>" }, written())
    assert.are.equal(2, runs)
  end)

  it("stops a running source when the picker closes", function()
    local cancelled = false
    Fzf.pick_fancy({
      prompt = "pick",
      many = false,
      items = function(emit)
        emit(items)
        return function()
          cancelled = true
        end
      end,
    }, { on_choices = function() end })

    written()
    captured.opts.winopts.on_close()
    assert.is_true(cancelled)
  end)
end)
