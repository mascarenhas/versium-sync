
-- 
-- ldiff and lpatch - binary diff tools
--
-- (c) 2007  Wim Couwenberg
-- See the COPYRIGHT file for the licencse 
--

if #arg ~= 3 then
	print [[

ldiff.lua: create a (binary) diff between two versions of a file

usage: lua ldiff.lua <file1-name> <file2-name> <diff-file-name>

ldiff reads both files and creates a diff file (in a proprietary format).  The
files can be binary.  The lpatch tool can recreate file2 from file1 and the
resulting diff file.  Be careful, the diff file will be replaced if it already
exists.
]]
	return
end

local byte = string.byte
local type = type
local strsub = string.sub

-- subsample rate in bytes
local index_step = 8

-- maximum key size to consider
local key_size = 8000

-- minimal number of bytes in a match
local minimal_match = 48

-- key bytes to consider
local boffset = {}

-- initialize offsets with fibonacci sequence 0, 1, 2, 4, 7, 12, ...
-- (rather arbitrary)
do
	local p, q = 0, 0
	while q < key_size do
		boffset[#boffset + 1] = q
		p, q = q, p + q + 1
	end
end

-- compare texts at key offsets
local function cmp(txt1, idx1, txt2, idx2, bindex)
	repeat
		bindex = bindex + 1
		local offset = boffset[bindex]
		if not offset then return end

		local b1 = byte(txt1, idx1 + offset)
		local b2 = byte(txt2, idx2 + offset)
		if not b1 or b1 ~= b2 then return b1 and b2, bindex end
	until false
end

-- insert a substring starting at index i into a trie
local function insert(tab, text, sub)
	-- used to remember the location of a leaf 
	local parent, child

	-- locate first different byte
	local b, bindex = cmp(text, 1, text, sub, 0) 

	-- only insert if a difference is found
	while b do
		-- compute branch key from index and byte
		local key = bindex*256 + b

		-- if at a leaf then extend it
		if child then
			parent[child] = {
				index = tab,
				[key] = sub,
			}
			break
		end

		-- locate branch
		parent, tab = tab, tab[key]

		if not tab then
			-- create new leaf
			parent[key] = sub
			break
		elseif type(tab) == "table" then
			-- continue search from an inner node
			b, bindex = cmp(text, tab.index, text, sub, bindex)
		else
			-- continue search from a leaf
			child = key
			b, bindex = cmp(text, tab, text, sub, bindex)
		end
	end
end

-- build a sparse index trie for a text
local function trie(msg)

	-- start with the whole message at the root
	local tab = {}

	-- insert substrings
	for i = index_step + 1, #msg, index_step do
		insert(tab, msg, i)
	end

	return tab
end

-- find a chunk of message of at least a minimal size in the trie
local function find(tab, text, msg, sub, minsize)
	-- start at index 1 of text
	local idx = 1

	-- start search at root
	local b, bindex = cmp(text, 1, msg, sub, 0)

	-- descend down trie
	while b do
		-- locate branch
		tab = tab[256*bindex + b]

		if not tab then
			-- not found
			break
		elseif type(tab) == "table" then
			-- continue search from inner node
			idx = tab.index
			b, bindex = cmp(text, idx, msg, sub, bindex)
		else
			-- arrived at leaf (no difference found)
			bindex = nil
			idx = tab
			break
		end
	end

	-- check upper bound for match
	if not bindex or boffset[bindex] >= minsize then
		-- find maximal exact match
		local len = 0
		repeat
			local b1 = byte(text, idx + len)
			local b2 = byte(msg, sub + len)
			if not b1 or b1 ~= b2 then break end
			len = len + 1
		until false

		if len >= minsize then
			return idx, len
		end
	end
end

local function diff(txt1, txt2, out)
	-- index reference text
	local tab = trie(txt1)

	local len2 = #txt2
	local pos1, pos2, sub = 1, 1, 1

	-- process txt2 from first byte to last
	while sub <= len2 do
		-- locate a matching chunk in index trie
		local idx, len = find(tab, txt1, txt2, sub, minimal_match)

		if not idx then
			-- proceed to next position if not found
			sub = sub + 1
		else
			if pos2 < sub then
				-- copy literal bytes from txt2
				if pos1 == 1 then out "0" end
				out(" " .. (sub - pos2) .. "\n")
				out(strsub(txt2, pos2, sub - 1))

				-- start on new line
				out "\n"
			elseif pos1 > 1 then
				-- make sure the next command is on a new line
				out "\n"
			end

			-- insert an optional movement
			if idx > pos1 then
				out("+" .. (idx - pos1) .. " ")
			elseif pos1 - idx > idx then
				out("@" .. idx .. " ")
			elseif idx ~= pos1 then
				out((idx - pos1) .. " ")
			end

			-- copy chunk from txt1
			out(len)

			-- adjust positions in txt1 and txt2
			pos1 = idx + len
			sub = sub + len
			pos2 = sub
		end
	end

	-- copy the remaining literal bytes from txt2
	if pos2 < sub then
		-- copy literal bytes from txt2
		if pos1 == 1 then out "0" end
		out(" " .. (sub - pos2) .. "\n")
		out(strsub(txt2, pos2, sub - 1))

		-- start on new line
		out "\n"
	elseif pos1 > 1 then
		-- make sure the next command is on a new line
		out "\n"
	end
end

local function read(name)
	-- open file binary to prevent crlf conversion
	local f, e = io.open(name, "rb")

	if not f then
		return nil, e
	end

	-- read entire contents at once
	local m = f:read "*a"
	f:close()

	return m
end

local txt1, err = read(arg[1])
if not txt1 then
	io.stderr:write("could not open ", err, "\n")
	return
end

local txt2, err = read(arg[2])
if not txt2 then
	io.stderr:write("could not open ", err, "\n")
	return
end

local out, err = io.open(arg[3], "wb")
if not out then
	io.stderr:write("could not open ", err, "\n")
	return
end

diff(txt1, txt2, function(chunk)
	out:write(chunk)
end)

out:close()
