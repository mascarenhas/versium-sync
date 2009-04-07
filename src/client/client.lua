#!/usr/bin/env lua

require "luarocks.require"
require "versium.filedir"
require "versium.sync"

local blacklist = versium.sync.blacklist{ "@SyncClient_Metadata" }

local server = (select(1, ...))

local repo = versium.filedir.new{ (select(2, ...)) }

local meta_info = repo:get_node_info("@SyncClient_Metadata")

if not meta_info then
  versium.sync.client_checkout(repo, server, blacklist)
else
  local commit_ok
  repeat
    local conflicts = versium.sync.client_update(repo, server, blacklist)
    for _, conflict in ipairs(conflicts) do
      print("conflict on node ", conflict.id)
    end
    commit_ok = versium.sync.client_commit(repo, server, blacklist)
  end
end
