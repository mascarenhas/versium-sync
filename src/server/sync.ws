#!/usr/bin/env wsapi.cgi

require "wsapi.request"
require "wsapi.response"
require "versium.filedir"

local repo

local function get_full_history(node_id)
  local history = {}
  local versions = repo:get_node_history(node_id)
  local prev = repo:get_node(node_id, versions[#versions].version)
  table.insert(history, { versions[#versions], prev })
  for i = #versions - 1, 1, -1 do
    local next = repo:get_node(node_id, versions[i].version)
    table.insert(history, { versions[i], diff })
    prev = next
  end
  return history
end

local function sync_changes(wsapi_env, timestamp)
  local sync_meta_node = repo:get_node("@SyncServer_Metadata", timestamp)
  if not sync_meta_node then
     return 500, {}, "Sync Timestamp Not Found"
  else
    local sync_meta_info = dostring(sync_meta_node)
    local diff = {}
    for _, node_id in repo:get_node_ids() do
      if sync_meta_info[node_id] then
	local old_version = sync_meta_info[node_id]
        table.insert(diff, { "change", node_id, 
			     versions = get_diff_history(node_id, old_version) })
	sync_meta_info[node_id] = nil
      else
	table.insert(diff, { "add", node_id, versions = get_full_history(node_id) })
      end
    end
    for node_id, _ in pairs(sync_meta_info) do
      table.insert(diff, { "delete", node_id })
    end
    return 200, {}, serialize(diff)
  end
end

local function run(wsapi_env)
  repo = repo or versium.filedir.new{ wsapi_env.APP_PATH }
  local path_info, method = wsapi_env.PATH_INFO, tolower(wsapi_env.REQUEST_METHOD)
  if path_info:match("^/%d+$") and method == "get" then
    local timestamp = tonumber(path_info:match("^/(%d+)$")
    return sync_changes(wsapi_env, timestamp)
  elseif path_info == "/" and method == "get" then
    return sync_all(wsapi_env) 
  elseif path_info == "/" and method == "post" then
    return sync_update(wsapi_env)
  else
    return 500, {}, "Invalid Request"
  end
end

return run
