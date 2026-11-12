--!nonstrict
local presentation = require("./presentation.luau")
local sessions = noctalia.state.get("sessions") or {}

function onClick()
  noctalia.togglePanel("local/pi-noctalia:sessions")
end

local function render()
  barWidget.setVisible(#sessions > 0)
  local limit = math.clamp(noctalia.getConfig("max_visible"), 1, 10)
  local vertical = barWidget.isVertical()
  local children = { ui.label({ text = "π", fontWeight = "bold" }) }
  for i = 1, math.min(#sessions, limit) do
    local session = sessions[i]
    local _, glyph, color = presentation.status(session)
    local contents = { ui.glyph({ name = glyph, color = color }) }
    if not vertical then
      table.insert(contents, ui.label({ text = presentation.short(session.name, 12), color = color, maxWidth = 110, maxLines = 1 }))
    end
    table.insert(children, ui.row({
      key = session.instanceId, gap = 4, paddingH = 3, align = "center",
      tooltip = presentation.details(session), onClick = "onClick",
    }, contents))
  end
  if #sessions > limit then
    table.insert(children, ui.button({
      key = "overflow", text = "+" .. (#sessions - limit), variant = "ghost",
      tooltip = "Show all Pi sessions", onClick = "onClick",
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
