--!nonstrict
local presentation = require("./presentation.luau")
local focusGhostty = require("./focus.luau")
local sessions = noctalia.state.get("sessions") or {}

function openPanel()
  noctalia.togglePanel("local/pi-noctalia:sessions")
end

local function live(id, target, piPid)
  for _, session in ipairs(sessions) do
    if session.instanceId == id and session.state ~= "disconnected" and session.pid == piPid
        and session.ghostty and session.ghostty.pid == target.pid
        and session.ghostty.surfaceId == target.surfaceId
        and session.ghostty.piStartTicks == target.piStartTicks then
      local stat = noctalia.readFile("/proc/" .. piPid .. "/stat")
      local fields = type(stat) == "string" and stat:match("^.*%) (.*)")
      if not fields then return false end
      local index = 0
      for field in fields:gmatch("%S+") do
        index += 1
        if index == 1 and (field == "Z" or field == "X" or field == "x") then return false end
        if index == 20 then return field == target.piStartTicks end
      end
    end
  end
  return false
end

local function focusSession(id)
  for _, session in ipairs(sessions) do
    if session.instanceId == id then
      if session.ghostty then
        local target, piPid = session.ghostty, session.pid
        local stillLive = function() return live(id, target, piPid) end
        if stillLive() then focusGhostty(target, stillLive) else openPanel() end
      else
        openPanel()
      end
      return
    end
  end
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
      tooltip = presentation.details(session), onClick = function() focusSession(id) end,
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
