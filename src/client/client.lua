#!/usr/bin/env lua

require "luarocks.require"
require "versium.filedir"
require "versium.sync.client"

local blacklist = versium.sync.client.blacklist{ "@SyncClient_Metadata" }

local server = (select(1, ...))

local repo = versium.filedir.new{ (select(2, ...)) }

local meta_info = repo:get_node_info("@SyncClient_Metadata")

local sync = versium.sync.new(repo, server, blacklist)

local commit_ok
repeat
  print("Updating...")
  local conflicts = sync:update()
  for _, conflict in ipairs(conflicts) do
    print("update conflict on node ", conflict.id)
  end
  print("Commiting...")
  commit_conflicts = sync:commit()
  for _, conflict in ipairs(commit_conflicts) do
    print("commit conflict on node ", conflict)
  end
until #commit_conflicts == 0
