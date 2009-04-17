
require "versium.sync.serialize"

local http = require "socket.http"

module("versium.sync.client", package.seeall)

-- makes blacklist function from list of blacklisted nodes
function blacklist(list)
  local bl = {}
  for _, node in ipairs(list) do bl[node] = true end
  return function (node) return bl[node] end
end

local methods = {}

function new(repo, server, blacklist)
  return setmetatable({ repo = repo, server = server, blacklist = blacklist },
		      { __index = methods })
end

-- rebuilds client's sync metadata, needs fresh snapshot from server
local function new_sync_node(repo, server_info, blacklist)
  local si = { server_nodes = server_info.nodes, server_ts = server_info.timestamp,
	       nodes = {} }
  for _, id in ipairs(repo:get_node_ids()) do
    if not blacklist(id) then
      si.nodes[id] = repo:get_node_info(id).version
    end
  end
  repo:save_version("@SyncClient_Metadata", serialize(si), "Sync Client")
end

-- updates client's sync metadta, changed is a set of changed nodes in the
-- client, server_info is the new server snapshot (optional, keeps the old
-- one by default
local function update_sync_node(repo, changed, server_info)
  local si = loadstring(repo:get_node("@SyncClient_Metadata"))()
  for id, version in pairs(changed) do
    si.nodes[id] = version
  end
  if server_info then
    si.server_nodes, si.server_ts = server_info.nodes, server_info.timestamp
  end
  repo:save_version("@SyncClient_Metadata", serialize(si), "Sync Client")
end

-- checks out fresh copy of server's repository
local function checkout(repo, server, blacklist)
  local res, status = http.request(server)
  if status ~= 200 then error("versium sync server error: " .. res) end
  local remote_repo = loadstring(res)()
  local nodes, remote_repo.nodes = remote_repo.nodes, {}
  for i, node in ipairs(nodes) do
    repo:save_version(node[2], node[4], node[3].author, node[3].comment,
		      node[3].extra, node[3].timestamp)
    remote_repo.nodes[node[2]] = node[3].version
  end
  new_sync_node(repo, remote_repo, blacklist)
  return {} -- no conflicts on checkout
end

-- returns set of local changes to commit
local function local_changes(repo, si, blacklist)
  si = si or loadstring(repo:get_node("@SyncClient_Metadata"))()
  local changes = {}
  for _, id in ipairs(repo:get_node_ids()) do
    if si.nodes[id] then
      if si.nodes[id] ~= repo:get_node_info(id).version then
	changes[id] = "change"
      end
    elseif not blacklist(id) then
      changes[id] = "add"
    end
  end
  return changes, si.server_nodes, si.server_ts
end

-- updates local repository with server changes, returns list
-- of update conflicts (and keeps those nodes unchanged)
function methods:update()
  local repo, srv, bl = self.repo, self.server, self.blacklist
  local sn = repo:get_node("@SyncClient_Metadata")
  if not sn then
    return checkout(repo, srv, bl)
  end
  local si = loadstring(sn)()
  local changes, server_nodes, server_ts = local_changes(repo, si, bl)
  local res, status = http.request(srv .. "/" .. server_ts)
  if status ~= 200 then error("versium sync server error: " .. res) end
  local server_changes = loadstring(res)()
  local conflicts = {}
  local changed = {}
  server_ts = server_changes.timestamp
  for _, change in ipairs(server_changes.nodes) do
    server_nodes[change[2]] = change[3].version
    if local_changes[change[2]] then
      local node = repo:get_node(change[2])
      if node ~= change[4] then -- conflict
	table.insert(conflicts, {  id = change[2], info = change[3], text = change[4] })
      end
    else
      changed[change[2]] = repo:save_version(change[2], change[4], change[3].author, 
					     change[3].comment, change[3].extra, change[3].timestamp)
    end
  end
  update_sync_node(repo, changed, { nodes = server_nodes, timestamp = server_ts })
  return conflicts
end

-- updates local repository with list of conflicts
function methods:solve_conflicts(conflicts)
  local repo = self.repo
  local changed = {}
  for _, conflict in ipairs(conflicts) do
    changed[conflict.id] = repo:save_version(conflict.id, conflict.text, conflict.info.author,
					     conflict.info.comment, conflict.info.extra,
					     conflict.info.timestamp)
  end
  update_sync_node(repo, changed)
end

local function set2list(s)
  local l = {}
  for k, _ in pairs(s) do l[#l + 1] = k end
  return l
end

-- commits local changes to server, returns true if commit
-- was successful, false if there where version conflicts
-- during commit
function methods:commit()
  local repo, srv, bl = self.repo, self.server, self.blacklist
  local changes, server_nodes, server_ts = local_changes(repo, bl)
  local to_commit = {}
  for id, action in pairs(changes) do
    table.insert(to_commit, { action, id, repo:get_node_info(id),
			      repo:get_node(id), server_nodes[id] or "new" })
  end
  if #to_commit ~= 0 then
    local res, status = http.request(srv .. "/" .. server_ts, serialize(to_commit))
    if status == 200 then
      local response = loadstring(res)()
      local changed = {}
      for id, action in ipairs(changes) do
	if not response.conflicts[node_id] then 
	  changed[id] = repo:get_node_info(id).version 
	  server_nodes[id] = response.delta[id]
	end
      end
      update_sync_node(repo, changed, { nodes = server_nodes, timestamp = response.timestamp })
      return set2list(response.conflicts)
    end
    error("versium sync server error: " .. res)
  end
end

