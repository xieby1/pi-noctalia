--!nonstrict
local presentation = require("./presentation.luau")
local focusSession = require("./focus.luau")
local sessions = noctalia.state.get("sessions") or {}
local hovered
local selected

local function canFocus(session)
  return session.ghostty ~= nil and session.state ~= "disconnected"
end

function onCloseClicked()
  panel.close()
end

local function render()
  local rows = {}
  for _, session in ipairs(sessions) do
    local status, glyph, color = presentation.status(session)
    local id = session.instanceId
    local focusable = canFocus(session)
    table.insert(rows, ui.column({
      key = id, gap = 5, padding = 8, radius = 6,
      fill = focusable and selected == id and "primary/0.25"
        or focusable and hovered == id and "primary/0.20" or "surface/0",
      border = focusable and selected == id and "primary" or "primary/0", borderWidth = 2,
      onClick = focusable and function() if focusSession(id) then panel.close() end end or nil,
      onHover = focusable and "onRowHover" or nil,
    }, {
      ui.row({ gap = 8, align = "center" }, {
        ui.glyph({ name = glyph, color = color }),
        ui.label({ text = session.name, fontWeight = "bold", flexGrow = 1, maxLines = 2 }),
        ui.label({ text = focusable and status or status .. " · Focus unavailable", color = color }),
      }),
      ui.label({ text = session.cwd, maxLines = 2 }),
      ui.label({ text = session.model ~= "" and session.model or "No model selected", fontSize = 12 }),
      ui.label({ text = "PID " .. session.pid .. " · " .. session.sessionId, fontSize = 11, color = "on_surface/0.65", maxLines = 2 }),
      ui.label({ text = session.instanceId, fontSize = 11, color = "on_surface/0.65" }),
      ui.separator({ spacing = 4 }),
    }))
  end
  if #rows == 0 then
    table.insert(rows, ui.label({ text = "No interactive Pi sessions.\nNew sessions appear within 15 seconds.", maxLines = 3 }))
  end
  panel.render(ui.column({ gap = 12, padding = 12, flexGrow = 1 }, {
    ui.row({ align = "center", gap = 8 }, {
      ui.label({ text = "Pi Sessions (" .. #sessions .. ")", fontWeight = "bold", flexGrow = 1 }),
      ui.button({ key = "close", glyph = "close", tooltip = "Close", selected = selected == "close", onClick = "onCloseClicked" }),
    }),
    ui.scroll({ flexGrow = 1, revealKey = selected ~= "close" and selected or "" }, rows),
  }))
end

function onRowHover(state, id)
  if state == "true" then hovered = id
  elseif hovered == id then hovered = nil end
  render()
end

function onKey(chord, pressed)
  if not pressed then return end
  if chord == "Return" or chord == "KP_Enter" or chord == "space" then
    if selected == "close" then panel.close()
    elseif selected and focusSession(selected) then panel.close() end
    return
  end
  local tab = chord == "Tab" or chord == "shift+Tab" or chord == "shift+ISO_Left_Tab"
  local ids = {}
  if tab then table.insert(ids, "close") end
  for _, session in ipairs(sessions) do
    if canFocus(session) then table.insert(ids, session.instanceId) end
  end
  if #ids == 0 then selected = nil; render(); return end
  local backwards = chord == "Up" or chord == "shift+Tab" or chord == "shift+ISO_Left_Tab"
  local index = backwards and #ids + 1 or 0
  for i, id in ipairs(ids) do
    if id == selected then index = i; break end
  end
  selected = ids[(index - 1 + (backwards and -1 or 1)) % #ids + 1]
  render()
end

function onOpen()
  selected, hovered = nil, nil
  sessions = noctalia.state.get("sessions") or {}
  render()
end

noctalia.state.watch("sessions", function(value)
  sessions = value or {}
  render()
end)
