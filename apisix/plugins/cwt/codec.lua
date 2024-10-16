
local basex, alphabets, basex_meta, basex_instance_meta

alphabets = {
    BASE16LOWER = '0123456789abcdef',
    BASE16UPPER = '0123456789ABCDEF',
    BASE58BITCOIN = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz',
    BASE58FLICKR = '123456789abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ',
    BASE58RIPPLE = 'rpshnaf39wBUDNEGHJKLM4PQRST7VWXYZ2bcdeCg65jkm8oFqi1tuvAxyz',
    BASE58JINGTUM = 'jpshnaf39wBUDNEGHJKLM4PQRST7VWXYZ2bcdeCg65rkm8oFqi1tuvAxyz',
}

basex = {
    _VERSION = '0.2.0',
    _URL = 'https://github.com/un-def/lua-basex',
    _DESCRIPTION = 'Base encoding/decoding of any given alphabet ' ..
            'using bitcoin style leading zero compression',
    _LICENSE = [[
    Copyright (c) 2016-2017, un.def
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:

     * Redistributions of source code must retain the above copyright notice,
       this list of conditions and the following disclaimer.
     * Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.

    THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND ANY
    EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
    WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
    DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE FOR ANY
    DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
    (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
    SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
    CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
    LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
    OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
    DAMAGE.
  ]],
    alphabets = alphabets,
}

basex_meta = {
    __call = function(_, alphabet)
        local alphabet_map = {}
        local base = #alphabet
        local leader = alphabet:sub(1, 1)
        for i = 1, base do
            alphabet_map[alphabet:sub(i, i)] = i - 1
        end
        local basex_instance = {
            alphabet = alphabet,
            base = base,
            leader = leader,
            alphabet_map = alphabet_map,
        }
        return setmetatable(basex_instance, basex_instance_meta)
    end,

    __index = function(cls, key)
        local alphabet = cls.alphabets[key:upper()]
        if not alphabet then return nil end
        local basex_instance = cls(alphabet)
        cls[key] = basex_instance
        return basex_instance
    end
}

basex_instance_meta = {
    __index = {
        encode = function(self, source)
            if #source == 0 then return '' end

            local digits = {0}

            for i = 1, #source do
                local carry = source:byte(i, i)
                for j = 1, #digits do
                    carry = carry + digits[j] * 256
                    digits[j] = carry % self.base
                    carry = math.floor(carry / self.base)
                end
                while carry > 0 do
                    table.insert(digits, carry % self.base)
                    carry = math.floor(carry / self.base)
                end
            end

            for k = 1, #source-1 do
                if source:byte(k, k) ~= 0 then break end
                table.insert(digits, 0)
            end

            local ii = 1
            local jj = #digits
            local tmp
            while true do
                tmp = self.alphabet:sub(digits[ii]+1, digits[ii]+1)
                digits[ii] = self.alphabet:sub(digits[jj]+1, digits[jj]+1)
                digits[jj] = tmp
                ii = ii + 1
                jj = jj - 1
                if ii > jj then break end
            end

            return table.concat(digits)
        end,

        decode = function(self, str)
            if #str == 0 then return '' end

            local bytes = {0}

            local value, carry
            for i = 1, #str do
                value = self.alphabet_map[str:sub(i, i)]
                if value == nil then
                    return nil, 'Non-base' .. self.base .. ' character'
                end
                carry = value
                for j = 1, #bytes do
                    carry = carry + bytes[j] * self.base
                    bytes[j] = carry % 256
                    carry = math.floor(carry / 256)
                end
                while carry > 0 do
                    table.insert(bytes, carry % 256)
                    carry = math.floor(carry / 256)
                end
            end

            for k = 1, #str-1 do
                if str:sub(k, k) ~= self.leader then break end
                table.insert(bytes, 0)
            end

            local decoded = ''
            for i = #bytes, 1, -1 do
                decoded = decoded .. string.char(bytes[i])
            end

            return decoded
        end
    }
}

return setmetatable(basex, basex_meta)