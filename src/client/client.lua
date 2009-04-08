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
  local conflicts = sync:update()
  for _, conflict in ipairs(conflicts) do
    print("conflict on node ", conflict.id)
  end
  commit_ok = sync:commit()
until commit_ok
