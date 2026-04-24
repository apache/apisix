--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

--- Built-in PII category catalog for ai-pii-sanitizer.
-- Each entry: {name, tag, regex, validate?}
-- * tag   : placeholder prefix, e.g. "EMAIL" -> "[EMAIL_0]"
-- * regex : ngx.re-compatible pattern; the first capture group (if any) is
--           the value to replace, otherwise the whole match is replaced.
-- * validate(match) -> boolean : optional; when present, a positive regex
--           hit is only recorded as PII if validate() returns true.

local string = string
local tonumber = tonumber

local _M = {}


-- Luhn check for credit cards. Strips spaces/dashes first.
local function luhn_valid(s)
    local digits = s:gsub("[%s%-]", "")
    if #digits < 12 or #digits > 19 then
        return false
    end
    local sum = 0
    local alt = false
    for i = #digits, 1, -1 do
        local d = tonumber(digits:sub(i, i))
        if not d then
            return false
        end
        if alt then
            d = d * 2
            if d > 9 then d = d - 9 end
        end
        sum = sum + d
        alt = not alt
    end
    return sum % 10 == 0
end


-- Basic E.164-ish phone regex. Deliberately lenient in the local-number
-- branch (US hyphenated) because over-matching gets Luhn'd out downstream
-- only for credit_card; for phones we rely on the +CC prefix or a
-- parenthesized area code to avoid eating every 10-digit number.
local catalog = {
    {
        name = "email",
        tag  = "EMAIL",
        regex = [[[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}]],
    },
    {
        name = "us_ssn",
        tag  = "SSN",
        -- xxx-xx-xxxx, excluding some invalid leading groups
        regex = [[(?<!\d)(?!000|666|9\d{2})\d{3}-(?!00)\d{2}-(?!0000)\d{4}(?!\d)]],
    },
    {
        name = "credit_card",
        tag  = "CREDIT_CARD",
        -- Major brands. Luhn check gates the final decision.
        regex = [[(?<!\d)(?:\d[ \-]?){12,18}\d(?!\d)]],
        validate = luhn_valid,
    },
    {
        name = "phone",
        tag  = "PHONE",
        -- Accept +CC form or US (NPA) NXX-XXXX / NPA-NXX-XXXX.
        regex = [[(?:\+\d{1,3}[\s\-]?)?(?:\(\d{3}\)[\s\-]?|\d{3}[\s\-])\d{3}[\s\-]\d{4}]],
    },
    {
        name = "ipv4",
        tag  = "IPV4",
        regex = [[(?<!\d)(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)(?!\d)]],
    },
    {
        name = "ipv6",
        tag  = "IPV6",
        -- Compressed form allowed. Not exhaustive, but covers the
        -- textual representations users actually paste.
        regex = [[(?:[A-Fa-f0-9]{1,4}:){2,7}[A-Fa-f0-9]{1,4}|::(?:[A-Fa-f0-9]{1,4}:){0,6}[A-Fa-f0-9]{1,4}]],
    },
    {
        name = "iban",
        tag  = "IBAN",
        regex = [[\b[A-Z]{2}\d{2}[A-Z0-9]{11,30}\b]],
    },
    {
        name = "aws_access_key",
        tag  = "AWS_ACCESS_KEY",
        regex = [[\b(?:AKIA|ASIA|AIDA|AROA|AIPA|ANPA|ANVA|ASCA)[A-Z0-9]{16}\b]],
    },
    {
        name = "openai_key",
        tag  = "OPENAI_KEY",
        regex = [[\bsk-(?:proj-)?[A-Za-z0-9_\-]{20,}\b]],
    },
    {
        name = "github_token",
        tag  = "GITHUB_TOKEN",
        regex = [[\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36}\b]],
    },
    {
        name = "jwt",
        tag  = "JWT",
        regex = [[\beyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\b]],
    },
    {
        name = "generic_api_key",
        tag  = "API_KEY",
        -- Heuristic: key-like context + high-entropy token. We keep this
        -- last so more specific categories match first.
        regex = [[(?i)\b(?:api[_\-]?key|apikey|secret|token)\b\s*[:=]\s*['"]?([A-Za-z0-9_\-]{24,})['"]?]],
    },
    {
        name = "bearer_token",
        tag  = "BEARER_TOKEN",
        regex = [[(?i)\bbearer\s+([A-Za-z0-9_\-\.=]{20,})\b]],
    },
}


-- Index by name for O(1) lookup when a user enables a subset.
local by_name = {}
for _, entry in ipairs(catalog) do
    by_name[entry.name] = entry
end

-- Cached name list, built once at module load. Callers must treat the
-- returned table as read-only.
local all_names_cached = {}
for i, entry in ipairs(catalog) do
    all_names_cached[i] = entry.name
end

function _M.all_names()
    return all_names_cached
end


function _M.get(name)
    return by_name[name]
end


function _M.iter()
    return ipairs(catalog)
end


return _M
