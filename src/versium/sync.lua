
require "versium.sync.serialize"

local http = require "socket.http"

module("versium.sync", package.seeall)

-- makes blacklist function from list of blacklisted nodes
function blacklist(list)
  local bl = {}
  for _, node in ipairs(list) do bl[node] = true end
  return function (node) return bl[node] end
end

-- updates server sync metadata - snapshot of current node versions
-- returns new timestamp
local function server_update_sync_info(repo, blacklist)
  local sync_info = {}
  for _, node_id in ipairs(repo:get_node_ids()) do
     if not blacklist(node_id) then
       local version = repo:get_node_info(node_id).version
       sync_info[node_id] = version
     end
  end
  repo:save_version("@SyncServer_Metadata", serialize(sync_info), "Sync System")
  return repo:get_node_info("@SyncServer_Metadata").version
end

-- writes first metadata node if it not exists yet
function init_server(repo, blacklist)
  local sync_info = repo:get_node_info("@SyncServer_Metadata")
  if not sync_info then
    server_update_sync_info(repo, blacklist)
  end
end

-- checks if there were changes since timestamp
local function has_changes(repo, blacklist, timestamp)
  local sync_meta_node = repo:get_node("@SyncServer_Metadata", timestamp)
  local sync_meta_info = loadstring(sync_meta_node)()
  for _, node_id in pairs(repo:get_node_ids()) do
    if sync_meta_info[node_id] then
      if repo:get_node_info(node_id).version ~= sync_meta_info[node_id] then
	return true
      end
      sync_meta_info[node_id] = nil
    elseif not blacklist(node_id) then
      return true
    end
  end
  for node_id, _ in pairs(sync_meta_info) do
    return true
  end
  return false
end

-- get changes since timestamp and updates current metadata
-- returns changes and newest timestamp
function get_changes(repo, blacklist, timestamp)
  timestamp = timestamp or repo:get_node_info("@SyncServer_Metadata").version
  local sync_meta_node = repo:get_node("@SyncServer_Metadata", timestamp)
  if not sync_meta_node then
    error("versium sync: timestamp not found")
  else
    local sync_meta_info = loadstring(sync_meta_node)()
    local changes = {}
    for _, node_id in pairs(repo:get_node_ids()) do
      if sync_meta_info[node_id] then
	if repo:get_node_info(node_id).version ~= sync_meta_info[node_id] then
	   table.insert(changes, { "change", node_id, repo:get_node_info(node_id), 
				   repo:get_node(node_id) })
	end
	sync_meta_info[node_id] = nil
      elseif not blacklist(node_id) then
	table.insert(changes, { "add", node_id, repo:get_node_info(node_id), 
				repo:get_node(node_id) })
      end
    end
    for node_id, _ in pairs(sync_meta_info) do
      table.insert(changes, { "delete", node_id })
    end
    timestamp =  repo:get_node_info("@SyncServer_Metadata").version
    if has_changes(repo, blacklist, timestamp) then
      timestamp = server_update_sync_info(repo, blacklist)
    end
    return { nodes = changes, server_ts = timestamp }
  end
end

-- gets entire repository (as changeset) and latest timestamp
function get_all(repo, blacklist)
  local data = { nodes = {} }
  for _, node_id in ipairs(repo:get_node_ids()) do
    if not blacklist(node_id) then
      table.insert(data.nodes, { "add", node_id, repo:get_node_info(node_id), 
				 repo:get_node(node_id) })
    end
  end
  data.server_ts = repo:get_node_info("@SyncServer_Metadata").version
  if has_changes(repo, blacklist, data.server_ts) then
    data.server_ts = server_update_sync_info(repo, blacklist)
  end
  return data
end

-- applies changes to repository, returns list of version conflicts
function server_update(repo, changes, blacklist)
  local version_conficts = {}
  for _, change in ipairs(changes) do
    if change[1] == "delete" then
      if not repo:save_version(change[2], "", "Sync System", nil, nil, nil, changes[5]) then
	version_conflicts[change[2]] = true
      end
    else
      if not repo:save_version(change[2], change[4], change[3].author, change[3].comment,
			       change[3].extra, change[3].timestamp, change[5]) then
	version_conflicts[change[2]] = true
      end
    end
  end
  return version_conflicts
end

-- rebuilds client's sync metadata, needs fresh snapshot from server
local function client_new_sync_info(repo, server_info, blacklist)
  local sync_info = { server_info = server_info, nodes = {} }
  for _, node_id in ipairs(repo:get_node_ids()) do
    if not blacklist(node_id) then
      sync_info.nodes[node_id] = repo:get_node_info(node_id).version
    end
  end
  repo:save_version("@SyncClient_Metadata", serialize(sync_info), "Sync Client")
end

-- updates client's sync metadta, changed is a set of changed nodes in the
-- client, server_info is the new server snapshot (optinal, keeps the old
-- one by default
local function client_update_sync_info(repo, changed, server_info)
  local sync_info = loadstring(repo:get_node("@SyncClient_Metadata"))()
  for node_id, version in pairs(changed) do
    sync_info.nodes[node_id] = version
  end
  sync_info.server_info = server_info or sync_info.server_info
  repo:save_version("@SyncClient_Metadata", serialize(sync_info), "Sync Client")
end

-- returns set of local changes to commit
local function get_local_changes(repo, blacklist)
  local last_update = loadstring(repo:get_node("@SyncClient_Metadata"))()
  local changes = {}
  for _, node_id in ipairs(repo:get_node_ids()) do
    if last_update.nodes[node_id] then
      if last_update.nodes[node_id] ~= repo:get_node_info(node_id).version then
	changes[node_id] = "change"
      end
    elseif not blacklist(node_id) then
      changes[node_id] = "add"
    end
  end
  return changes, last_update.server_info
end

-- checks out fresh copy of server's repository
function client_checkout(repo, server, blacklist)
  local res, status = http.request(server)
  if status ~= 200 then error("versium sync server error: " .. res) end
  local remote_repo = loadstring(res)()
  for i, node in ipairs(remote_repo.nodes) do
    repo:save_version(node[2], node[4], node[3].author, node[3].comment,
		      node[3].extra, node[3].timestamp)
    remote_repo.nodes[i] = node[3].version
  end
  client_new_sync_info(repo, remote_repo, blacklist)
end

-- updates local repository with server changes, returns list
-- of update conflicts (and keeps those nodes unchanged)
function client_update(repo, server, blacklist)
  local local_changes, server_info = get_local_changes(repo, blacklist)
  local res, status = http.request(server .. "/" .. server_info.server_ts)
  if status ~= 200 then error("versium sync server error: " .. res) end
  local server_changes = loadstring(res)()
  local conflicts = {}
  local changed = {}
  server_info.server_ts = server_changes.server_ts
  for _, change in ipairs(server_changes.nodes) do
    server_info.nodes[change[2]] = change[3].version
    if local_changes[change[2]] then
      local node = repo:get_node(change[2])
      if node ~= change[4] then -- conflict
	table.insert(conflicts, {  change[2], change[3], change[4] })
      end
    else
      if change[1] == "delete" then
	repo:save_version(change[2], "", "Sync Client")
      else
	repo:save_version(change[2], change[4], change[3].author, 
			  change[3].comment, change[3].extra, change[3].timestamp)
      end
      changed[change[2]] = repo:get_node_info(change[2]).version
    end
  end
  client_update_sync_info(repo, changed, server_info)
  return conflicts
end

-- updates local repository with list of conflicts
function solve_conflicts(repo, conflicts)
  local changed = {}
  for _, conflict in ipairs(conflicts) do
    repo:save_version(conflict[1], conflict[3], conflict[2].author,
		      conflict[2].comment, conflict[2].extra,
		      conflict[2].timestamp)
    changed[conflict[1]] = repo:get_node_info(conflict[1]).version
  end
  client_update_sync_info(repo, changed)
end

-- commits local changes to server, returns true if commit
-- was successful, false if there where version conflicts
-- during commit
function client_commit(repo, server, blacklist)
  local local_changes, server_info = get_local_changes(repo, blacklist)
  local to_commit = {}
  for node_id, action in pairs(local_changes) do
    table.insert(to_commit, { action, node_id, repo:get_node_info(node_id),
			      repo:get_node(node_id), server_info.nodes[node_id] or "new" })
  end
  if #to_commit ~= 0 then
    local res, status = http.request(server, serialize(to_commit))
    if status == 200 then
      local conflicts = loadstring(res)()
      local changed, has_conflict = {}, false
      for node_id, action in ipairs(local_changes) do
	if not conflicts[node_id] then 
	  changed[node_id] = repo:get_node_info(node_id).version 
	else
	  has_conflicts = true
	end
      end
      client_update_sync_info(repo, changed)
      return not has_conflicts
    end
    error("versium sync server error: " .. res)
  end
end
