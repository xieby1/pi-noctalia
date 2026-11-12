-- Sources are embedded by check.sh; the actual entry files run in isolated environments below.
local function check(condition, message)
  assert(condition, message)
end

local now = 1000000
local shared = {}
local watchers = {}
local decoded = {}
local renders = {}
local intervals = {}
local vertical = false
local visible = false
local panelId = nil
local closed = false
local constructors = {}
for _, kind in ipairs({ "row", "column", "glyph", "label", "button", "scroll", "separator" }) do
  constructors[kind] = function(props, children) return { kind = kind, props = props, children = children or {} } end
end

local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for k, v in pairs(value) do result[k] = copy(v) end
  return result
end

local function loadEntry(name)
  local env = setmetatable({}, { __index = getfenv() })
  local cache = {}
  env.noctalia = {
    nowMs = function() return now end,
    setUpdateInterval = function(value) intervals[name] = value end,
    getConfig = function(key) check(key == "max_visible", "undeclared setting"); return 3 end,
    togglePanel = function(id) panelId = id end,
    json = { decode = function(raw) return copy(decoded[raw]) end },
    state = {
      get = function(key) return copy(shared[key]) end,
      set = function(key, value)
        shared[key] = copy(value)
        for _, callback in ipairs(watchers[key] or {}) do callback(copy(value)) end
      end,
      watch = function(key, callback)
        watchers[key] = watchers[key] or {}
        table.insert(watchers[key], callback)
      end,
    },
  }
  env.ui = constructors
  env.barWidget = {
    render = function(tree) renders.widget = tree end,
    setVisible = function(value) visible = value end,
    isVertical = function() return vertical end,
  }
  env.panel = {
    render = function(tree) renders.panel = tree end,
    close = function() closed = true end,
  }
  env.require = function(path)
    if cache[path] == nil then
      local moduleEnv = setmetatable({}, { __index = env })
      cache[path] = setfenv(assert(loadstring(sources[path], path)), moduleEnv)()
    end
    return cache[path]
  end
  setfenv(assert(loadstring(sources["./" .. name .. ".luau"], name)), env)()
  return env
end

local service = loadEntry("service")
local widget = loadEntry("widget")
local panel = loadEntry("panel")
panel.onOpen()
check(#shared.sessions == 0 and not visible, "empty state hides the bar")
check(intervals.service == 5000 and intervals.widget == nil, "only service has an expiry timer")
check(renders.panel.children[2].children[1].props.text:find("No interactive") ~= nil, "empty panel explains missing sessions")

local serial = 0
local function send(event, value)
  serial += 1
  local raw = tostring(serial)
  decoded[raw] = value
  service.onIpc(event, raw)
end
local function sample(n, sequence)
  return {
    schema = 1, instanceId = string.format("00000000-0000-4000-8000-%012d", n),
    sequence = sequence or 1, pid = 100 + n, startedAt = 1000 + n,
    sessionId = "same-session", name = "Project " .. n, cwd = "/projects/demo",
    model = "provider/model", state = "idle", aborted = false,
  }
end

for _, n in ipairs({ 4, 2, 1, 3 }) do send("upsert", sample(n)) end
check(#shared.sessions == 4, "same logical session has four independent instances")
check(shared.sessions[1].pid == 101 and shared.sessions[4].pid == 104, "creation order is independent of arrival order")
check(visible and #renders.widget.children == 5, "three chips plus header and overflow")
check(renders.widget.children[5].props.text == "+1", "overflow count")
check(#renders.panel.children[2].children == 4, "panel lists every session")
check(renders.widget.children[2].props.tooltip:find("/projects/demo", 1, true) ~= nil, "tooltip contains full project")
widget.onClick()
check(panelId == "local/pi-noctalia:sessions", "bar opens the session panel")
panel.onCloseClicked()
check(closed, "panel can close")

local working = sample(2, 2)
working.state = "working"
working.startedAt = 0
send("upsert", working)
check(shared.sessions[2].state == "working" and shared.sessions[2].startedAt == 1002, "state changes cannot reorder an instance")
send("upsert", sample(2, 1))
check(shared.sessions[2].state == "working", "old updates are ignored")
now += 40000
send("upsert", working) -- duplicate does not refresh liveness
now += 5000
service.update()
check(shared.sessions[2].state == "disconnected", "duplicates cannot keep a dead instance alive")
local recovered = sample(2, 3)
recovered.state = "waiting"
send("upsert", recovered)
check(shared.sessions[2].state == "waiting", "new heartbeat restores live status")

send("remove", { schema = 1, instanceId = recovered.instanceId, sequence = 2 })
check(#shared.sessions == 4, "old removal cannot erase a newer update")
send("remove", { schema = 1, instanceId = recovered.instanceId, sequence = 4 })
send("upsert", sample(2, 5))
check(#shared.sessions == 3, "removed identity cannot be resurrected by a late update")

for _, field in ipairs({ "schema", "instanceId", "sequence", "pid", "startedAt", "sessionId", "name", "cwd", "model", "state", "aborted" }) do
  local invalid = sample(5)
  invalid[field] = {}
  send("upsert", invalid)
  check(#shared.sessions == 3, "reject invalid " .. field)
end
for _, change in ipairs({ { "sequence", 0 }, { "pid", -1 }, { "startedAt", math.huge }, { "state", "done" }, { "name", "" }, { "name", string.rep("x", 513) }, { "name", string.char(255) }, { "cwd", "/a" .. string.char(10) .. "b" } }) do
  local invalid = sample(5)
  invalid[change[1]] = change[2]
  send("upsert", invalid)
  check(#shared.sessions == 3, "reject out-of-range " .. change[1])
end
service.onIpc("upsert", "invalid JSON")
service.onIpc("upsert", string.rep("x", 16385))
send("unknown", sample(5))
check(#shared.sessions == 3, "invalid envelopes leave registry intact")

now += 300000
service.update()
check(#shared.sessions == 0 and not visible, "expired instances disappear")
send("upsert", sample(1, 10))
service = loadEntry("service")
check(#shared.sessions == 0, "service reload clears obsolete shared state")
send("upsert", sample(1, 11))
check(#shared.sessions == 1 and visible, "full heartbeat repopulates a restarted service")
local details = renders.widget.children[2].props.tooltip
check(details:find("same-session", 1, true) ~= nil, "logical identity is visible")
check(details:find(sample(1).instanceId, 1, true) ~= nil, "instance identity is visible")

local unicode = sample(6)
unicode.name = string.rep("界", 20)
send("upsert", unicode)
local short = renders.widget.children[3].children[2].props.text
check(utf8.len(short) == 13, "truncation preserves UTF-8 and appends an ellipsis")
local stopped = sample(6, 2)
stopped.aborted = true
send("upsert", stopped)
check(renders.widget.children[3].props.tooltip:find("Stopped", 1, true) ~= nil, "aborted is not shown as successful completion")
vertical = true
loadEntry("widget")
check(renders.widget.kind == "column", "vertical bar uses a column")
check(#renders.widget.children[2].children == 1, "vertical chips stay within the bar thickness")
print("Pi Sessions checks passed")
