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

-- ProtoJSON well-known types whose wire representation differs from JSON.
-- Protobuf state must be selected by caller before using this module.
local pb = require("pb")
local core = require("apisix.core")
local M = {}
local type, tonumber, error = type, tonumber, error
local pairs, ipairs, next, getmetatable = pairs, ipairs, next, getmetatable
local floor, abs = math.floor, math.abs
local format, concat = string.format, table.concat
local wrapper_types = {
    [".google.protobuf.StringValue"]="string",
    [".google.protobuf.BoolValue"]="bool",
    [".google.protobuf.Int32Value"]="int32",
    [".google.protobuf.UInt32Value"]="uint32",
    [".google.protobuf.Int64Value"]="int64",
    [".google.protobuf.UInt64Value"]="uint64",
    [".google.protobuf.FloatValue"]="float",
    [".google.protobuf.DoubleValue"]="double",
    [".google.protobuf.BytesValue"]="bytes",
}
local custom = {
    [".google.protobuf.Timestamp"]=true,
    [".google.protobuf.Duration"]=true,
    [".google.protobuf.FieldMask"]=true,
    [".google.protobuf.Any"]=true,
    [".google.protobuf.Struct"]=true,
    [".google.protobuf.Value"]=true,
    [".google.protobuf.ListValue"]=true,
    -- Empty is specially encoded as value:{} by Go protojson, but the
    -- published ProtoJSON spec treats it as a normal zero-field message.
    -- The outer Any conversion handles this interoperability case.
}
for n in pairs(wrapper_types) do custom[n]=true end
function M.is_custom(name) return custom[name] or false end
local function bad(text) error("ProtoJSON WKT: " .. text, 0) end
local function decimal(v)
    if type(v)=="string" then
        local stripped=v:gsub("^#", "")
        return tonumber(stripped)
    end
    return v or 0
end
local function frac(nanos)
    if nanos==0 then return "" end
    if nanos % 1000000 == 0 then return (".%03d"):format(nanos/1000000) end
    if nanos % 1000 == 0 then return (".%06d"):format(nanos/1000) end
    return (".%09d"):format(nanos)
end
local function leap(y)
    return y%4==0 and (y%100~=0 or y%400==0)
end
local function valid_date(y,m,d)
    if y<1 or y>9999 or m<1 or m>12 or d<1 then return false end
    local nd = ({31,28,31,30,31,30,31,31,30,31,30,31})[m]
    return d<=nd+(m==2 and leap(y) and 1 or 0)
end
local function days_from_civil(y,m,d)
    if m<=2 then y=y-1 end
    local era=floor(y/400)
    local yoe=y-era*400
    local mp=m+(m>2 and -3 or 9)
    local doy=floor((153*mp+2)/5)+d-1
    local doe=yoe*365+floor(yoe/4)-floor(yoe/100)+doy
    return era*146097+doe-719468
end
local function civil_from_days(days)
    local z=days+719468
    local era=floor(z/146097)
    local doe=z-era*146097
    local yoe=floor((doe-floor(doe/1460)+floor(doe/36524)-floor(doe/146096))/365)
    local y=yoe+era*400
    local doy=doe-(365*yoe+floor(yoe/4)-floor(yoe/100))
    local mp=floor((5*doy+2)/153)
    local d=doy-floor((153*mp+2)/5)+1
    local m=mp+(mp<10 and 3 or -9)
    if m<=2 then y=y+1 end
    return y,m,d
end
local function timestamp_to(v)
    if type(v)~="string" then bad("Timestamp must be RFC3339 string") end
    local y,mo,d,h,mi,s,rest=v:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)(.*)$")
    if not y then bad("invalid Timestamp") end
    y,mo,d,h,mi,s=tonumber(y),tonumber(mo),tonumber(d),tonumber(h),tonumber(mi),tonumber(s)
    if not valid_date(y,mo,d) or h>23 or mi>59 or s>59 then bad("invalid Timestamp date/time") end
    local fractional, zone=rest:match("^(%.%d+)(.*)$")
    if not fractional then fractional=""; zone=rest end
    if #fractional>10 then bad("Timestamp precision exceeds nanoseconds") end
    local offset=0
    if zone~="Z" then
        local sign, zh, zm=zone:match("^([+-])(%d%d):(%d%d)$")
        if not sign or tonumber(zh)>23 or tonumber(zm)>59 then bad("invalid Timestamp timezone") end
        offset=(tonumber(zh)*60+tonumber(zm))*60*(sign=="+" and 1 or -1)
    end
    local seconds=days_from_civil(y,mo,d)*86400+h*3600+mi*60+s-offset
    if seconds < -62135596800 or seconds > 253402300799 then
        bad("Timestamp outside supported range")
    end
    local nanos=tonumber((fractional:sub(2).."000000000"):sub(1,9)) or 0
    return {seconds=seconds, nanos=nanos}
end
local function timestamp_from(v)
    local seconds,nanos=decimal(v.seconds),v.nanos or 0
    if type(seconds)~="number" or seconds<-62135596800 or seconds>253402300799 or
       nanos<0 or nanos>=1000000000 or nanos~=floor(nanos) then bad("invalid Timestamp") end
    local days=floor(seconds/86400)
    local tod=seconds-days*86400
    local y,m,d=civil_from_days(days)
    return ("%04d-%02d-%02dT%02d:%02d:%02d%sZ"):format(
        y,m,d,floor(tod/3600),floor(tod%3600/60),tod%60,frac(nanos))
end
local function duration_to(v)
    if type(v)~="string" then bad("Duration must be a string") end
    local neg, whole, fractional=v:match("^(%-?)(%d+)%.(%d+)s$")
    if not whole then neg,whole=v:match("^(%-?)(%d+)s$"); fractional="" end
    if not whole or #fractional>9 then bad("invalid Duration") end
    local secs=tonumber(whole)
    if not secs or secs>315576000000 then bad("Duration outside supported range") end
    local nanos=tonumber((fractional.."000000000"):sub(1,9)) or 0
    if neg=="-" then secs=-secs; nanos=-nanos end
    return {seconds=secs,nanos=nanos}
end
local function duration_from(v)
    local secs,nanos=decimal(v.seconds),v.nanos or 0
    if type(secs)~="number" or abs(secs)>315576000000 or abs(nanos)>=1000000000 or
       nanos~=floor(nanos) or (secs>0 and nanos<0) or (secs<0 and nanos>0) then
        bad("invalid Duration")
    end
    local negative=secs<0 or nanos<0
    return (negative and "-" or "")..format("%.0f", abs(secs))..frac(abs(nanos)).."s"
end
local function fieldmask_to(v)
    if type(v)~="string" then bad("FieldMask must be string") end
    local paths={}
    if v=="" then return {paths=paths} end
    for path in (v..","):gmatch("(.-),") do
        if path=="" or path:find("_") or path:find("[^%w%.]") then bad("invalid FieldMask path") end
        paths[#paths+1]=path:gsub("(%u)", function(c) return "_"..c:lower() end)
    end
    return {paths=paths}
end
local function fieldmask_from(v)
    local paths={}
    for _,path in ipairs(v.paths or {}) do
        paths[#paths+1]=path:gsub("_([a-z])", function(c) return c:upper() end)
    end
    return concat(paths,",")
end
function M.to_proto(ft,v,encode_field,deep_to,null,opts)
    if ft==".google.protobuf.Timestamp" then return timestamp_to(v) end
    if ft==".google.protobuf.Duration" then return duration_to(v) end
    if ft==".google.protobuf.FieldMask" then return fieldmask_to(v) end
    if ft==".google.protobuf.Empty" then
        if type(v)~="table" or next(v)~=nil then bad("Empty must be {}") end
        return {}
    end
    if wrapper_types[ft] then return {value=encode_field(wrapper_types[ft],v)} end
    if ft==".google.protobuf.Any" then
        if type(v)~="table" or type(v["@type"])~="string" then bad("Any requires @type") end
        local name=v["@type"]:match("/([^/]+)$")
        if not name or not pb.type("."..name) then bad("Any type unavailable in descriptor") end
        local message
        if name == "google.protobuf.Empty" then
            -- Accept both Go {value:{}} and specification {@type only}.
            if v.value ~= nil and (type(v.value) ~= "table" or
                getmetatable(v.value) == core.json.array_mt or
                next(v.value) ~= nil) then
                bad("Any<Empty> value must be an empty object")
            end
            message = {}
        elseif M.is_custom("."..name) then
            if v.value == nil then bad("Any special WKT requires value") end
            message=deep_to("."..name,v.value)
        else
            local contents={}
            for k,value in pairs(v) do if k~="@type" then contents[k]=value end end
            message=deep_to("."..name,contents)
        end
        local bytes=pb.encode("."..name,message)
        if not bytes then bad("failed to encode Any payload") end
        return {type_url=v["@type"],value=bytes}
    end
    return nil
end
function M.from_proto(ft,v,decode_field,deep_from,opts)
    if ft==".google.protobuf.Timestamp" then return timestamp_from(v) end
    if ft==".google.protobuf.Duration" then return duration_from(v) end
    if ft==".google.protobuf.FieldMask" then return fieldmask_from(v) end
    if ft==".google.protobuf.Empty" then return {} end
    if wrapper_types[ft] then
        local scalar = v.value
        if scalar == nil then
            local t = wrapper_types[ft]
            if t == "bool" then scalar = false
            elseif t == "string" or t == "bytes" then scalar = ""
            else scalar = 0 end
        end
        return decode_field(wrapper_types[ft],scalar)
    end
    if ft==".google.protobuf.Any" then
        local name=v.type_url and v.type_url:match("/([^/]+)$")
        if not name or not pb.type("."..name) then bad("Any type unavailable in descriptor") end
        local contents=pb.decode("."..name,v.value or "")
        if not contents then bad("failed to decode Any payload") end
        local converted=deep_from("."..name,contents)
        if name == "google.protobuf.Empty" then
            local result = {["@type"] = v.type_url}
            if opts and opts.any_empty_format == "go" then
                result.value = {}
            end
            return result
        end
        if M.is_custom("."..name) then
            return {["@type"]=v.type_url,value=converted}
        end
        converted["@type"]=v.type_url
        return converted
    end
    return nil
end
return M
