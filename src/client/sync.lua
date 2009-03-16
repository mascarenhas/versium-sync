#!/usr/bin/env lua

require "luarocks.require"
require "versium.filedir"
require "serialize"
local http = require "socket.http"

local blacklist = { ["@SyncClient_Metadata"] = true }

local repo = versium.filedir.new{ "./versium" }

local sync_info = repo:get_node("@SyncClient_Metadata")

local function save_sync_info(server_ts)
  local sync_info = { server_ts = server_ts, nodes = {} }
  for _, node_id in ipairs(repo:get_node_ids()) do
    if not blacklist[node_id] then
      sync_info.nodes[node_id] = repo:get_node_info(node_id).version
    end
  end
  repo:save_version("@SyncClient_Metadata", serialize(sync_info), "Sync Client")
end

local function reflect_changes(nodes)
  for _, node_id in ipairs(repo:get_node_ids()) do
    if nodes[node_id] then
      if nodes[node_id] == repo:get_node_info(node_id).version then
	nodes[node_id] = nil
      else
	nodes[node_id] = "change"
      end
    elseif not blacklist[node_id] then
      nodes[node_id] = "add"
    end
  end
end

if not sync_info then
  local res, status = http.request("http://localhost:8080/sync/sync.ws")
  if status ~= 200 then error(res) end
  local data = loadstring(res)()
  for _, node in ipairs(data) do
    repo:save_version(node[2], node[4], node[3].author, node[3].comment,
		      node[3].extra, node[3].timestamp)
  end
  local res, status = http.request("http://localhost:8080/sync/sync.ws", "return {}")
  if status ~= 200 then error(res) end
  save_sync_info(res)
else
  sync_info = loadstring(sync_info)()
  reflect_changes(sync_info.nodes)
  local res, status = http.request("http://localhost:8080/sync/sync.ws/" .. sync_info.server_ts)
  if status ~= 200 then error(res) end
  local server_diff = loadstring(res)()
  for _, node_diff in ipairs(server_diff) do
    if sync_info.nodes[node_diff[2]] and
       repo:get_node(node_diff[2]) ~= node_diff[4] then -- conflict
      error("sync conflict")
    else
      if node_diff[1] == "delete" then
	repo:save_version(node_diff[2], "", "Sync Client")
      else
	 repo:save_version(node_diff[2], node_diff[4], node_diff[3].author, 
			   node_diff[3].comment, node_diff[3].extra, node_diff[3].timestamp)
      end
    end
  end
  local changes = {}
  for node_id, action in pairs(sync_info.nodes) do
    table.insert(changes, { action, node_id, repo:get_node_info(node_id), 
			    repo:get_node(node_id) })
  end
  if #server_diff == 0 and #changes == 0 then
    print("No changes on server")
  else
    local res, status = http.request("http://localhost:8080/sync/sync.ws", serialize(changes))
    if status ~= 200 then error(res) end
    save_sync_info(res)
  end
end
