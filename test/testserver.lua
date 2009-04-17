#!/usr/bin/env lua

local pipe = io.popen("dirname `pwd`")
local base_path = pipe:read("*line")
pipe:close()

package.path = base_path .. "/src/?.lua;" .. package.path

require"luarocks.require"
require"xavante"
require"wsapi.xavante"
require"lfs"

local webdir = base_path .. "/src/server"

xavante.start_message(function (ports)
			assert(ports)
		      end)

xavante.HTTP{
  server = { host = "*", port = 8080 },
  defaultHost = {
    rules = {
      {
	match = { "%.ws$", "%.ws/" },
	with = wsapi.xavante.makeGenericHandler(webdir)
      }
    }
  }
}

assert(pcall(xavante.start, function ()
			      return lfs.attributes(webdir .. "/stop")
			    end, 0))
