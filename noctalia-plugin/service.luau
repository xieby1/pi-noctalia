--!nonstrict
-- Own the registry once, independently of widget placements and open panels.
local records = {}
local removed = {}
local staleMs = 45000
local expiryMs = 300000

local function integer(value, minimum)
  return type(value) == "number" and value == value and value <= 9007199254740991
    and value >= minimum and value % 1 == 0
end

local function text(value, maximum, allowEmpty)
  return type(value) == "string" and #value <= maximum
    and (allowEmpty or #value > 0) and utf8.len(value) ~= nil
    and not string.find(value, "%c")
end

local function identity(value)
  return type(value) == "table" and value.schema == 1
    and text(value.instanceId, 36, false) and #value.instanceId == 36
    and string.match(value.instanceId, "^[%x%-]+$") ~= nil
    and integer(value.sequence, 1)
end

local function snapshot(value)
  return identity(value) and integer(value.pid, 1) and integer(value.startedAt, 0)
    and text(value.sessionId, 512, false) and text(value.name, 512, false)
    and text(value.cwd, 4096, false) and text(value.model, 1024, true)
    and (value.state == "working" or value.state == "idle" or value.state == "waiting")
    and type(value.aborted) == "boolean"
end

local function publish()
  local sessions = {}
  for id, record in pairs(records) do
    local item = table.clone(record.value)
    if record.stale then item.state = "disconnected" end
    table.insert(sessions, item)
  end
  table.sort(sessions, function(a, b)
    if a.startedAt == b.startedAt then return a.instanceId < b.instanceId end
    return a.startedAt < b.startedAt
  end)
  noctalia.state.set("sessions", sessions)
end

function onIpc(event, payload)
  if (event ~= "upsert" and event ~= "remove") or type(payload) ~= "string" or #payload > 16384 then return end
  local value = noctalia.json.decode(payload)
  if not identity(value) then return end
  local id = value.instanceId
  local previous = records[id]
  if removed[id] or (previous and value.sequence <= previous.value.sequence) then return end
  local now = noctalia.nowMs()
  if event == "remove" then
    records[id] = nil
    removed[id] = now
    publish()
  elseif snapshot(value) then
    -- Copy only contract fields: unknown payload data cannot leak into the UI.
    records[id] = { receivedAt = now, stale = false, value = {
      schema = 1, instanceId = id, sequence = value.sequence,
      pid = value.pid, startedAt = previous and previous.value.startedAt or value.startedAt,
      sessionId = value.sessionId, name = value.name, cwd = value.cwd,
      model = value.model, state = value.state, aborted = value.aborted,
    } }
    publish()
  end
end

function update()
  local now = noctalia.nowMs()
  local changed = false
  for id, record in pairs(records) do
    local age = now - record.receivedAt
    if age >= expiryMs then
      records[id] = nil
      changed = true
    elseif age >= staleMs and not record.stale then
      record.stale = true
      changed = true
    end
  end
  for id, time in pairs(removed) do
    if now - time >= expiryMs then removed[id] = nil end
  end
  if changed then publish() end
end

noctalia.setUpdateInterval(5000)
-- A reloaded service must not leave another VM's old session list visible.
publish()
