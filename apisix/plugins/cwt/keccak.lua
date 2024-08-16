-- Copyright (c) 2014  Joseph Wallace
-- Copyright (c) 2015  Phil Leblanc
-- License: MIT - see LICENSE file
------------------------------------------------------------

-- 170612 SHA-3 padding fixed.
-- (reported by Michael Rosenberg https://github.com/doomrobo)

-- 150827 original code modified and optimized
-- (more than 2x performance improvement for sha3-512) --phil

-- Directly devived from a Keccak implementation by Joseph Wallace
-- published on the Lua mailing list in 2014
-- http://lua-users.org/lists/lua-l/2014-03/msg00905.html

local bit = require("bit")
local ffi = require("ffi")
local uint64 = ffi.typeof("uint64_t")
local struct = require("apisix.plugins.cwt.struct")
local bnot, band, bor, bxor, blshift, brshift = bit.bnot, bit.band, bit.bor, bit.bxor, bit.lshift, bit.rshift
local spack, sunpack = struct.pack, struct.unpack

-- the Keccak constants and functionality

local ROUNDS = 24

local roundConstants = {
	uint64(1LL),
	uint64(32898LL),
	uint64(-9223372036854742902LL),
	uint64(-9223372034707259392LL),
	uint64(32907LL),
	uint64(2147483649LL),
	uint64(-9223372034707259263LL),
	uint64(-9223372036854743031LL),
	uint64(138LL),
	uint64(136LL),
	uint64(2147516425LL),
	uint64(2147483658LL),
	uint64(2147516555LL),
	uint64(-9223372036854775669LL),
	uint64(-9223372036854742903LL),
	uint64(-9223372036854743037LL),
	uint64(-9223372036854743038LL),
	uint64(-9223372036854775680LL),
	uint64(32778LL),
	uint64(-9223372034707292150LL),
	uint64(-9223372034707259263LL),
	uint64(-9223372036854742912LL),
	uint64(2147483649LL),
	uint64(-9223372034707259384LL)
}

local rotationOffsets = {
-- ordered for [x][y] dereferencing, so appear flipped here:
{0, 36, 3, 41, 18},
{1, 44, 10, 45, 2},
{62, 6, 43, 15, 61},
{28, 55, 25, 21, 56},
{27, 20, 39, 8, 14}
}



-- the full permutation function
local function keccakF(st)
	local permuted = st.permuted
	local parities = st.parities
	for round = 1, ROUNDS do
--~ 		local permuted = permuted
--~ 		local parities = parities

		-- theta()
		for x = 1,5 do
			parities[x] = 0
			local sx = st[x]
			for y = 1,5 do parities[x] = bxor(parities[x], sx[y]) end
		end
		--
		-- unroll the following loop
		--for x = 1,5 do
		--	local p5 = parities[(x)%5 + 1]
		--	local flip = parities[(x-2)%5 + 1] ~ ( p5 << 1 | p5 >> 63)
		--	for y = 1,5 do st[x][y] = st[x][y] ~ flip end
		--end
		local p5, flip, s
		--x=1
		p5 = parities[2]
		flip = bxor(parities[5], bor(blshift(p5, 1), brshift(p5, 63)))
		s = st[1]
		for y = 1,5 do s[y] = bxor(s[y], flip) end
		--x=2
		p5 = parities[3]
		flip = bxor(parities[1], bor(blshift(p5, 1), brshift(p5, 63)))
		s = st[2]
		for y = 1,5 do s[y] = bxor(s[y], flip) end
		--x=3
		p5 = parities[4]
		flip = bxor(parities[2], bor(blshift(p5, 1), brshift(p5, 63)))
		s = st[3]
		for y = 1,5 do s[y] = bxor(s[y], flip) end
		--x=4
		p5 = parities[5]
		flip = bxor(parities[3], bor(blshift(p5, 1), brshift(p5, 63)))
		s = st[4]
		for y = 1,5 do s[y] = bxor(s[y], flip) end
		--x=5
		p5 = parities[1]
		flip = bxor(parities[4], bor(blshift(p5, 1), brshift(p5, 63)))
		s = st[5]
		for y = 1,5 do s[y] = bxor(s[y], flip) end

		-- rhopi()
		for y = 1,5 do
			local py = permuted[y]
			local r
			for x = 1,5 do
				s, r = st[x][y], rotationOffsets[x][y]
				py[(2*x + 3*y)%5 + 1] = bor(blshift(s, r), brshift(s, (64-r)))
			end
		end

		-- chi() - unroll the loop
		--for x = 1,5 do
		--	for y = 1,5 do
		--		local combined = (~ permuted[(x)%5 +1][y]) & permuted[(x+1)%5 +1][y]
		--		st[x][y] = permuted[x][y] ~ combined
		--	end
		--end

		local p, p1, p2
		--x=1
		s, p, p1, p2 = st[1], permuted[1], permuted[2], permuted[3]
		for y = 1,5 do s[y] = bxor(p[y], band(bnot(p1[y]), p2[y])) end
		--x=2
		s, p, p1, p2 = st[2], permuted[2], permuted[3], permuted[4]
		for y = 1,5 do s[y] = bxor(p[y], band(bnot(p1[y]), p2[y])) end
		--x=3
		s, p, p1, p2 = st[3], permuted[3], permuted[4], permuted[5]
		for y = 1,5 do s[y] = bxor(p[y], band(bnot(p1[y]), p2[y])) end
		--x=4
		s, p, p1, p2 = st[4], permuted[4], permuted[5], permuted[1]
		for y = 1,5 do s[y] = bxor(p[y], band(bnot(p1[y]), p2[y])) end
		--x=5
		s, p, p1, p2 = st[5], permuted[5], permuted[1], permuted[2]
		for y = 1,5 do s[y] = bxor(p[y], band(bnot(p1[y]), p2[y])) end

		-- iota()
		st[1][1] = bxor(st[1][1], roundConstants[round])
	end
end
 
local format = "<L"

local function absorb(st, buffer)

	local blockBytes = st.rate / 8
	local blockWords = blockBytes / 8

	-- append 0x01 byte and pad with zeros to block size (rate/8 bytes)
	local totalBytes = #buffer + 1
	-- for keccak (2012 submission), the padding is byte 0x01 followed by zeros
	-- for SHA3 (NIST, 2015), the padding is byte 0x06 followed by zeros

	-- Keccak:
	buffer = buffer .. ( '\x01' .. string.char(0):rep(blockBytes - (totalBytes % blockBytes)))

	-- SHA3:
	-- buffer = buffer .. ( '\x06' .. string.char(0):rep(blockBytes - (totalBytes % blockBytes)))
	totalBytes = #buffer

	--convert data to an array of u64
	local words = {}
	for i = 1, totalBytes - (totalBytes % 8), 8 do
		words[#words + 1] = sunpack(format, buffer, i)
	end

	local totalWords = #words

	-- OR final word with 0x80000000 to set last bit of state to 1
	words[totalWords] = bor(words[totalWords], uint64(-9223372036854775808LL))

	-- XOR blocks into state
	for startBlock = 1, totalWords, blockWords do
		local offset = 0
		for y = 1, 5 do
			for x = 1, 5 do
				if offset < blockWords then
					local index = startBlock+offset
					st[x][y] = bxor(st[x][y], words[index])
					offset = offset + 1
				end
			end
		end
		keccakF(st)
	end
end


-- returns [rate] bits from the state, without permuting afterward.
-- Only for use when the state will immediately be thrown away,
-- and not used for more output later
local function squeeze(st)
	local blockBytes = st.rate / 8
	local blockWords = blockBytes / 4
	-- fetch blocks out of state
	local hasht = {}
	local offset = 1
	for y = 1, 5 do
		for x = 1, 5 do
			if offset < blockWords then
				hasht[offset] = spack(format, st[x][y])
				offset = offset + 1
			end
		end
	end

	return table.concat(hasht)
end


-- primitive functions (assume rate is a whole multiple of 64 and length is a whole multiple of 8)

local function keccakHash(rate, length, data)
	local state = {	{0,0,0,0,0},
					{0,0,0,0,0},
					{0,0,0,0,0},
					{0,0,0,0,0},
					{0,0,0,0,0},
	}
	state.rate = rate
	-- these are allocated once, and reused
	state.permuted = { {}, {}, {}, {}, {}, }
	state.parities = {0,0,0,0,0}
	absorb(state, data)
	return squeeze(state):sub(1,length/8)
end

-- output raw bytestrings
local function keccak256Bin(data) return keccakHash(1088, 256, data) end
local function keccak512Bin(data) return keccakHash(576, 512, data) end

--return module
return {
	keccak256 = keccak256Bin,
	keccak512 = keccak512Bin,
}