--!nonstrict
local presentation = require("./presentation.luau")
local focusSession = require("./focus.luau")
local sessions = noctalia.state.get("sessions") or {}
local hovered

function onCloseClicked()
  panel.close()
end

local function render()
  local rows = {}
  for _, session in ipairs(sessions) do
    local status, glyph, color = presentation.status(session)
    local id = session.instanceId
    local focusable = session.ghostty ~= nil and session.state ~= "disconnected"
    table.insert(rows, ui.column({
      key = id, gap = 5, padding = 8, radius = 6,
      fill = focusable and hovered == id and "surface_container" or nil,
      onClick = focusable and function() focusSession(id) end or nil,
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
      ui.button({ glyph = "close", tooltip = "Close", onClick = "onCloseClicked" }),
    }),
    ui.scroll({ flexGrow = 1 }, rows),
  }))
end

function onRowHover(state, id)
  if state == "true" then hovered = id
  elseif hovered == id then hovered = nil end
  render()
end

function onOpen()
  sessions = noctalia.state.get("sessions") or {}
  render()
end

noctalia.state.watch("sessions", function(value)
  sessions = value or {}
  render()
end)
