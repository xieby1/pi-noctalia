--!nonstrict
-- Ghostty's GTK present-surface action is internal, so keep its D-Bus details here.
local path = "/com/mitchellh/ghostty"
local iface = "org.gtk.Actions"

return function(origin, stillLive)
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
