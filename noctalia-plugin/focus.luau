--!nonstrict
-- Ghostty's GTK present-surface action is internal, so keep its D-Bus details here.
local path = "/com/mitchellh/ghostty"
local iface = "org.gtk.Actions"

local function focusGhostty(origin, stillLive)
  local function unavailable()
    noctalia.notify("Pi Sessions", "Unable to focus this terminal")
  end

  local started = noctalia.runAsync({ "busctl", "--user", "--json=short", "list", "--no-pager" }, function(result)
    if result.exitCode ~= 0 or result.stdoutTruncated then unavailable(); return end
    local owners = noctalia.json.decode(result.stdout)
    if type(owners) ~= "table" then unavailable(); return end
    local names = {}
    for _, owner in ipairs(owners) do
      if type(owner) == "table" and owner.pid == origin.pid and
          type(owner.name) == "string" and owner.name:match("^:%d+%.%d+$") then
        table.insert(names, owner.name)
      end
    end

    local function tryName(i)
      local name = names[i]
      if not name then unavailable(); return end
      local probing = noctalia.runAsync({ "busctl", "--user", "--json=short", "call", name,
        path, iface, "Describe", "s", "present-surface" }, function(description)
        local action = description.exitCode == 0 and not description.stdoutTruncated
          and noctalia.json.decode(description.stdout)
        local data = type(action) == "table" and action.data
        local valid = type(data) == "table" and type(data[1]) == "table"
          and data[1][1] == true and data[1][2] == "t"
        if not valid then tryName(i + 1); return end
        if not stillLive() then return end
        if not noctalia.runAsync({ "busctl", "--user", "call", name, path, iface,
          "Activate", "sava{sv}", "present-surface", "1", "t", origin.surfaceId, "0" },
          function(focus) if focus.exitCode ~= 0 then unavailable() end end, 1500) then unavailable() end
      end, 1500)
      if not probing then tryName(i + 1) end
    end
    tryName(1)
  end, 1500)
  if not started then unavailable() end
end

local function live(id, target, piPid)
  for _, session in ipairs(noctalia.state.get("sessions") or {}) do
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

return function(id)
  for _, session in ipairs(noctalia.state.get("sessions") or {}) do
    if session.instanceId == id then
      if not session.ghostty then return false end
      local target, piPid = session.ghostty, session.pid
      local stillLive = function() return live(id, target, piPid) end
      if not stillLive() then return false end
      focusGhostty(target, stillLive)
      return true
    end
  end
  return false
end
