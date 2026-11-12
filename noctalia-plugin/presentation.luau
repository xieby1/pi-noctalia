-- Shared presentation rules for the compact bar and the complete session list.
local M = {}

function M.status(session)
  if session.state == "disconnected" then return "Disconnected", "wifi-off", "on_surface/0.5" end
  if session.state == "waiting" then return "Needs you", "help", "secondary" end
  if session.state == "working" then return "Working", "player-play", "primary" end
  if session.aborted then return "Stopped", "player-stop", "on_surface" end
  return "Idle", "check", "on_surface"
end

function M.short(text, length)
  local offset = utf8.offset(text, length + 1)
  return offset and (string.sub(text, 1, offset - 1) .. "…") or text
end

function M.details(session)
  local status = M.status(session)
  return table.concat({
    session.name .. " — " .. status,
    session.cwd,
    session.model ~= "" and session.model or "No model selected",
    "PID " .. session.pid .. " · Session " .. session.sessionId,
    "Instance " .. session.instanceId,
  }, "\n")
end

return M
