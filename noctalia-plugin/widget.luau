--!nonstrict
local presentation = require("./presentation.luau")
local focusSession = require("./focus.luau")
local sessions = noctalia.state.get("sessions") or {}

function openPanel()
  noctalia.togglePanel("local/pi-noctalia:sessions")
end

local function render()
  barWidget.setVisible(#sessions > 0)
  local limit = math.clamp(noctalia.getConfig("max_visible"), 1, 10)
  local vertical = barWidget.isVertical()
  local children = { ui.button({ key = "panel", text = "π", variant = "ghost", controlSize = "sm", onClick = "openPanel" }) }
  for i = 1, math.min(#sessions, limit) do
    local session = sessions[i]
    local id = session.instanceId
    local _, glyph = presentation.status(session)
    local name
    if not vertical then name = presentation.short(session.name, 12) end
    table.insert(children, ui.button({
      key = id, glyph = glyph, text = name,
      variant = "ghost", controlSize = "sm",
      tooltip = presentation.details(session), onClick = function() if not focusSession(id) then openPanel() end end,
    }))
  end
  if #sessions > limit then
    table.insert(children, ui.button({
      key = "overflow", text = "+" .. (#sessions - limit), variant = "ghost", controlSize = "sm",
      tooltip = "Show all Pi sessions", onClick = "openPanel",
    }))
  end
  local layout = vertical and ui.column or ui.row
  barWidget.render(layout({ gap = 6, align = "center" }, children))
end

noctalia.state.watch("sessions", function(value)
  sessions = value or {}
  render()
end)
render()
