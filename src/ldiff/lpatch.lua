
-- 
-- ldiff and lpatch - binary diff tools
--
-- (c) 2007  Wim Couwenberg
-- See the COPYRIGHT file for the licencse 
--

if #arg ~= 3 then
	print [[

lpatch.lua: a tool to patch a file with a diff created with ldiff.lua

usage: lua lpatch.lua <original-file-name> <diff-file-name> <target-file-name>

lpatch reads the first file, applies the diff file and writes the result to the
target file.  Be careful, the target file will be replaced if it already
exists.  Be extra careful because lpatch does not check if the diff file was in
fact created from the original file.
]]
	return
end

local find = string.find
local strsub = string.sub
local tonumber = tonumber

local function patch(txt, diff, out)
	local pos = 1
	local diffpos = 1
	local txtlen = #txt
	local difflen = #diff

	while diffpos <= difflen do
		-- look for a movement command (+/-/@)
		local from, to, whence, offset = find(diff, "^([%+%-%@])(%d+)%s+", diffpos)
		if whence then
			offset = tonumber(offset)
			if whence == "+" then
				pos = pos + offset
			elseif whence == "-" then
				pos = pos - offset
			else
				pos = offset
			end

			if pos < 1 or pos > txtlen then
				return nil, "position is outside original text"
			end

			diffpos = to + 1
		end
		
		-- look for a copy command and optional literal add command
		local from, to, copy, add = find(diff, "^(%d+)%s*(%d*)\n", diffpos)

		if not copy then
			return nil, "syntax error in diff"
		end

		copy = tonumber(copy)
		if copy > 0 then
			-- copy bytes from original text
			if pos + copy - 1 > txtlen then
				return nil, "copy range not contained in original text"
			end

			out(strsub(txt, pos, pos + copy - 1))
			pos = pos + copy
		end

		if add == "" then
			-- no literal bytes to copy
			diffpos = to + 1
		else
			-- copy literal bytes embedded in diff
			add = tonumber(add)

			if to + 1 > difflen or to + add > difflen then
				return nil, "literal range not contained in diff"
			end

			out(strsub(diff, to + 1, to + add))
			diffpos = to + add + 2
		end
	end

	if diffpos ~= difflen + 1 then
		return nil, "diff did not end properly"
	end

	return true
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

local txt, err = read(arg[1])
if not txt then
	io.stderr:write("could not open ", err, "\n")
	return
end

local diff, err = read(arg[2])
if not diff then
	io.stderr:write("could not open ", err, "\n")
	return
end

local out, err = io.open(arg[3], "wb")
if not out then
	io.stderr:write("could not open ", err, "\n")
	return
end

local rc, err = patch(txt, diff, function(chunk)
	out:write(chunk)
end)

out:close()

if not rc then
	io.stderr:write("patch error: ", err, "\n")
end
