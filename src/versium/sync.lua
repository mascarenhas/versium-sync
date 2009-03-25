
require "versium.sync.serialize"

local http = require "socket.http"

module("versium.sync", package.seeall)

function blacklist(list)
  local bl = {}
  for _, node in ipairs(list) do bl[node] = true end
  return function (node) return bl[node] end
end

local function server_update_sync_info(repo, blacklist, version_check)
  local sync_info = {}
  for _, node_id in ipairs(repo:get_node_ids()) do
     if not blacklist(node_id) then
       local version = repo:get_node_info(node_id).version
       sync_info[node_id] = version
     end
  end
  return repo:save_version("@SyncServer_Metadata", serialize(sync_info), "Sync System",
			   nil, nil, nil, version_check)
end

function init_server(repo, blacklist)
  local sync_info = repo:get_node_info("@SyncServer_Metadata")
  if not sync_info then
    return server_update_sync_info(repo, blacklist)
  end
end

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
    return { server_ts = repo:get_node_info("@SyncServer_Metadata").version, nodes = changes }
  end
end

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

function server_update(repo, timestamp, changes, blacklist)
  server_update_sync_info(repo, blacklist, timestamp)
  for _, change in ipairs(changes) do
    if change[1] == "delete" then
      repo:save_version(change[2], "", "Sync System")
    else
      repo:save_version(change[2], change[4], change[3].author, change[3].comment,
			change[3].extra, change[3].timestamp)
    end
  end
  return server_update_sync_info(repo, blacklist)
end

local function client_save_sync_info(repo, server_ts, blacklist)
  local sync_info = { server_ts = server_ts, nodes = {} }
  for _, node_id in ipairs(repo:get_node_ids()) do
    if not blacklist(node_id) then
      sync_info.nodes[node_id] = repo:get_node_info(node_id).version
    end
  end
  repo:save_version("@SyncClient_Metadata", serialize(sync_info), "Sync Client")
end

local function reflect_local_changes(repo, si_nodes, blacklist)
  for _, node_id in ipairs(repo:get_node_ids()) do
    if si_nodes[node_id] then
      if si_nodes[node_id] == repo:get_node_info(node_id).version then
	si_nodes[node_id] = nil
      else
	si_nodes[node_id] = "change"
      end
    elseif not blacklist(node_id) then
      si_nodes[node_id] = "add"
    end
  end
end

function client_checkout(repo, server, blacklist)
  local res, status = http.request(server)
  if status ~= 200 then error("versium sync server error: " .. res) end
  local changes = loadstring(res)()
  for _, node in ipairs(changes.nodes) do
    repo:save_version(node[2], node[4], node[3].author, node[3].comment,
		      node[3].extra, node[3].timestamp)
  end
  client_save_sync_info(repo, changes.server_ts, blacklist)
end

function client_update(repo, server, blacklist)
  local sync_info = loadstring(repo:get_node("@SyncClient_Metadata"))()
  reflect_local_changes(repo, sync_info.nodes, blacklist)
  local res, status = http.request(server .. "/" .. sync_info.server_ts)
  if status ~= 200 then error("versium sync server error: " .. res) end
  local server_changes = loadstring(res)()
  local conflicts = {}
  for _, change in ipairs(server_changes.nodes) do
    if sync_info.nodes[change[2]] then
      local node = repo:get_node(change[2])
      if node ~= change[4] then -- conflict
	table.insert(conflicts, {  id = change[2], server = { change[3], change[4] },
				   client = { repo:get_node_info(change[2]), node } })
	sync_info.nodes[change[2]] = nil
      else
	sync_info.nodes[change[2]] = nil
      end      
    else
      if change[1] == "delete" then
	repo:save_version(change[2], "", "Sync Client")
      else
	repo:save_version(change[2], change[4], change[3].author, 
			  change[3].comment, change[3].extra, change[3].timestamp)
      end
    end
  end
  local local_changes = {}
  for node_id, action in pairs(sync_info.nodes) do
    table.insert(local_changes, { action, node_id, repo:get_node_info(node_id), 
				  repo:get_node(node_id) })
  end
  return server_changes, local_changes, conflicts
end

function client_commit(repo, server, blacklist, server_changes, local_changes,
		       conflicts)
  for _, conflict in ipairs(conflicts) do
    if conflict.verdict == "server" then
      repo:save_version(conflict.id, conflict.server[2], conflict.server[1].author,
			conflict.server[1].comment, conflict[1].server.extra,
			conflict.server[1].timestamp)
    elseif conflict.verdict == "client" then
      table.insert(local_changes, { "change", conflict.id, conflict.client[1],
				    conflict.client[2] })
    else
      error("versium sync client: unsolved conflict")
    end
  end
  if #server_changes.nodes > 0 or #local_changes > 0 then
    local res, status = http.request(server .. "/" .. server_changes.server_ts, serialize(local_changes))
    if status ~= 200 then error("versium sync server error: " .. res) end
    client_save_sync_info(repo, loadstring(res)(), blacklist)
  end
end
