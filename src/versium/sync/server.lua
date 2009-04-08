
require "versium.sync.serialize"

module("versium.sync.server", package.seeall)

-- makes blacklist function from list of blacklisted nodes
function blacklist(list)
  local bl = {}
  for _, node in ipairs(list) do bl[node] = true end
  return function (node) return bl[node] end
end

local methods = {}

-- writes first (empty) metadata node if it does not exist yet
function new(repo, blacklist)
  local sync_info = repo:get_node_info("@SyncServer_Metadata")
  if not sync_info then
    assert(tonumber(repo:save_version("@SyncServer_Metadata", serialize({}), "Sync System")) == 1)
  end
  return setmetatable({ repo = repo, blacklist = blacklist }, { __index = methods })
end

-- get changes since timestamp and updates current metadata
-- returns changes and newest timestamp
function methods:update(ts)
  if not ts then return self:checkout() end
  local repo, bl = self.repo, self.blacklist
  local si = loadstring(repo:get_node("@SyncServer_Metadata", ts))()
  local changes = {}
  for _, id in pairs(repo:get_node_ids()) do
    if not bl(id) then
      local ni = repo:get_node_info(id)
      if si[id] and ni.version ~= si[id] then
	table.insert(changes, { "change", id, ni, repo:get_node(id, ni.version) })
      elseif not si[id] then
	table.insert(changes, { "add", id, ni, repo:get_node(id, ni.version) })
      end
      si[id] = ni.version
    end
  end
  if #changes > 0 then
    ts = repo:save_version("@SyncServer_Metadata", serialize(si), "Sync System")
  end
  return { nodes = changes, timestamp = ts }
end

-- gets entire repository (as changeset) and latest timestamp
function methods:checkout()
  local hist = repo:get_node_history("@SyncServer_Metadata")
  return self:update(hist[#hist].version)
end

-- applies changes to repository, returns set of version conflicts
function methods:commit(ts, changes)
  local repo, bl = self.repo, self.blacklist
  local conficts = {}
  local si_delta = {}
  for _, change in ipairs(changes) do
    local version = repo:save_version(change[2], change[4], change[3].author, change[3].comment,
				      change[3].extra, change[3].timestamp, change[5])
    if version then
      si[change[2]] = version
    else
      conflicts[change[2]] = true
    end
  end
  ts = repo:save_version("@SyncServer_Metadata", serialize(si), "Sync System")
  return { conflicts = conflicts, delta = si_delta, timestamp = ts }
end
