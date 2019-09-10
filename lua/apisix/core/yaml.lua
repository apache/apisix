-------------------------------------------------------------------------------
-- tinyyaml - YAML subset parser
-- https://github.com/peposso/lua-tinyyaml
-------------------------------------------------------------------------------

local table = table
local string = string
local schar = string.char
local ssub, gsub = string.sub, string.gsub
local sfind, smatch = string.find, string.match
local tinsert, tremove = table.insert, table.remove
local setmetatable = setmetatable
local pairs = pairs
local type = type
local tonumber = tonumber
local math = math
local getmetatable = getmetatable
local error = error

local UNESCAPES = {
  ['0'] = "\x00", z = "\x00", N    = "\x85",
  a = "\x07",     b = "\x08", t    = "\x09",
  n = "\x0a",     v = "\x0b", f    = "\x0c",
  r = "\x0d",     e = "\x1b", ['\\'] = '\\',
};

-------------------------------------------------------------------------------
-- utils
local function select(list, pred)
  local selected = {}
  for i = 0, #list do
    local v = list[i]
    if v and pred(v, i) then
      tinsert(selected, v)
    end
  end
  return selected
end

local function startswith(haystack, needle)
  return ssub(haystack, 1, #needle) == needle
end

local function ltrim(str)
  return smatch(str, "^%s*(.-)$")
end

local function rtrim(str)
  return smatch(str, "^(.-)%s*$")
end

-------------------------------------------------------------------------------
-- Implementation.
--
local class = {__meta={}}
function class.__meta.__call(cls, ...)
  local self = setmetatable({}, cls)
  if cls.__init then
    cls.__init(self, ...)
  end
  return self
end

function class.def(base, typ, cls)
  base = base or class
  local mt = {__metatable=base, __index=base}
  for k, v in pairs(base.__meta) do mt[k] = v end
  cls = setmetatable(cls or {}, mt)
  cls.__index = cls
  cls.__metatable = cls
  cls.__type = typ
  cls.__meta = mt
  return cls
end


local types = {
  null = class:def('null'),
  map = class:def('map'),
  omap = class:def('omap'),
  pairs = class:def('pairs'),
  set = class:def('set'),
  seq = class:def('seq'),
  timestamp = class:def('timestamp'),
}

local Null = types.null
function Null.__tostring() return 'yaml.null' end
function Null.isnull(v)
  if v == nil then return true end
  if type(v) == 'table' and getmetatable(v) == Null then return true end
  return false
end
local null = Null()

function types.timestamp:__init(y, m, d, h, i, s, f, z)
  self.year = tonumber(y)
  self.month = tonumber(m)
  self.day = tonumber(d)
  self.hour = tonumber(h or 0)
  self.minute = tonumber(i or 0)
  self.second = tonumber(s or 0)
  if type(f) == 'string' and sfind(f, '^%d+$') then
    self.fraction = tonumber(f) * math.pow(10, 3 - #f)
  elseif f then
    self.fraction = f
  else
    self.fraction = 0
  end
  self.timezone = z
end

function types.timestamp:__tostring()
  return string.format(
    '%04d-%02d-%02dT%02d:%02d:%02d.%03d%s',
    self.year, self.month, self.day,
    self.hour, self.minute, self.second, self.fraction,
    self:gettz())
end

function types.timestamp:gettz()
  if not self.timezone then
    return ''
  end
  if self.timezone == 0 then
    return 'Z'
  end
  local sign = self.timezone > 0
  local z = sign and self.timezone or -self.timezone
  local zh = math.floor(z)
  local zi = (z - zh) * 60
  return string.format(
    '%s%02d:%02d', sign and '+' or '-', zh, zi)
end


local function countindent(line)
  local _, j = sfind(line, '^%s+')
  if not j then
    return 0, line
  end
  return j, ssub(line, j+1)
end

local function parsestring(line, stopper)
  stopper = stopper or ''
  local q = ssub(line, 1, 1)
  if q == ' ' or q == '\t' then
    return parsestring(ssub(line, 2))
  end
  if q == "'" then
    local i = sfind(line, "'", 2, true)
    if not i then
      return nil, line
    end
    return ssub(line, 2, i-1), ssub(line, i+1)
  end
  if q == '"' then
    local i, buf = 2, ''
    while i < #line do
      local c = ssub(line, i, i)
      if c == '\\' then
        local n = ssub(line, i+1, i+1)
        if UNESCAPES[n] ~= nil then
          buf = buf..UNESCAPES[n]
        elseif n == 'x' then
          local h = ssub(i+2,i+3)
          if sfind(h, '^[0-9a-fA-F]$') then
            buf = buf..schar(tonumber(h, 16))
            i = i + 2
          else
            buf = buf..'x'
          end
        else
          buf = buf..n
        end
        i = i + 1
      elseif c == q then
        break
      else
        buf = buf..c
      end
      i = i + 1
    end
    return buf, ssub(line, i+1)
  end
  if q == '-' or q == ':' then
    if ssub(line, 2, 2) == ' ' or #line == 1 then
      return nil, line
    end
  end
  local buf = ''
  while #line > 0 do
    local c = ssub(line, 1, 1)
    if sfind(stopper, c, 1, true) then
      break
    elseif c == ':' and (ssub(line, 2, 2) == ' ' or #line == 1) then
      break
    elseif c == '#' and (ssub(buf, #buf, #buf) == ' ') then
      break
    else
      buf = buf..c
    end
    line = ssub(line, 2)
  end
  return rtrim(buf), line
end

local function isemptyline(line)
  return line == '' or sfind(line, '^%s*$') or sfind(line, '^%s*#')
end

local function startswithline(line, needle)
  return startswith(line, needle) and isemptyline(ssub(line, #needle+1))
end

local function parseflowstyle(line, lines)
  local stack = {}
  while true do
    if #line == 0 then
      if #lines == 0 then
        break
      else
        line = tremove(lines, 1)
      end
    end
    local c = ssub(line, 1, 1)
    if c == '#' then
      line = ''
    elseif c == ' ' or c == '\t' or c == '\r' or c == '\n' then
      line = ssub(line, 2)
    elseif c == '{' or c == '[' then
      tinsert(stack, {v={},t=c})
      line = ssub(line, 2)
    elseif c == ':' then
      local s = tremove(stack)
      tinsert(stack, {v=s.v, t=':'})
      line = ssub(line, 2)
    elseif c == ',' then
      local value = tremove(stack)
      if value.t == ':' or value.t == '{' or value.t == '[' then error() end
      if stack[#stack].t == ':' then
        -- map
        local key = tremove(stack)
        stack[#stack].v[key.v] = value.v
      elseif stack[#stack].t == '{' then
        -- set
        stack[#stack].v[value.v] = true
      elseif stack[#stack].t == '[' then
        -- seq
        tinsert(stack[#stack].v, value.v)
      end
      line = ssub(line, 2)
    elseif c == '}' then
      if stack[#stack].t == '{' then
        if #stack == 1 then break end
        stack[#stack].t = '}'
        line = ssub(line, 2)
      else
        line = ','..line
      end
    elseif c == ']' then
      if stack[#stack].t == '[' then
        if #stack == 1 then break end
        stack[#stack].t = ']'
        line = ssub(line, 2)
      else
        line = ','..line
      end
    else
      local s, rest = parsestring(line, ',{}[]')
      if not s then
        error('invalid flowstyle line: '..line)
      end
      tinsert(stack, {v=s, t='s'})
      line = rest
    end
  end
  return stack[1].v, line
end

local function parseblockstylestring(line, lines, indent)
  if #lines == 0 then
    error("failed to find multi-line scalar content")
  end
  local s = {}
  local firstindent = -1
  local endline = -1
  for i = 1, #lines do
    local ln = lines[i]
    local idt = countindent(ln)
    if idt <= indent then
      break
    end
    if ln == '' then
      tinsert(s, '')
    else
      if firstindent == -1 then
        firstindent = idt
      elseif idt < firstindent then
        break
      end
      tinsert(s, ssub(ln, firstindent + 1))
    end
    endline = i
  end

  local striptrailing = true
  local sep = '\n'
  local newlineatend = true
  if line == '|' then
    striptrailing = true
    sep = '\n'
    newlineatend = true
  elseif line == '|+' then
    striptrailing = false
    sep = '\n'
    newlineatend = true
  elseif line == '|-' then
    striptrailing = true
    sep = '\n'
    newlineatend = false
  elseif line == '>' then
    striptrailing = true
    sep = ' '
    newlineatend = true
  elseif line == '>+' then
    striptrailing = false
    sep = ' '
    newlineatend = true
  elseif line == '>-' then
    striptrailing = true
    sep = ' '
    newlineatend = false
  else
    error('invalid blockstyle string:'..line)
  end
  local eonl = 0
  for i = #s, 1, -1 do
    if s[i] == '' then
      tremove(s, i)
      eonl = eonl + 1
    end
  end
  if striptrailing then
    eonl = 0
  end
  if newlineatend then
    eonl = eonl + 1
  end
  for i = endline, 1, -1 do
    tremove(lines, i)
  end
  return table.concat(s, sep)..string.rep('\n', eonl)
end

local function parsetimestamp(line)
  local _, p1, y, m, d = sfind(line, '^(%d%d%d%d)%-(%d%d)%-(%d%d)')
  if not p1 then
    return nil, line
  end
  if p1 == #line then
    return types.timestamp(y, m, d), ''
  end
  local _, p2, h, i, s = sfind(line, '^[Tt ](%d+):(%d+):(%d+)', p1+1)
  if not p2 then
    return types.timestamp(y, m, d), ssub(line, p1+1)
  end
  if p2 == #line then
    return types.timestamp(y, m, d, h, i, s), ''
  end
  local _, p3, f = sfind(line, '^%.(%d+)', p2+1)
  if not p3 then
    p3 = p2
    f = 0
  end
  local zc = ssub(line, p3+1, p3+1)
  local _, p4, zs, z = sfind(line, '^ ?([%+%-])(%d+)', p3+1)
  if p4 then
    z = tonumber(z)
    local _, p5, zi = sfind(line, '^:(%d+)', p4+1)
    if p5 then
      z = z + tonumber(zi) / 60
    end
    z = zs == '-' and -tonumber(z) or tonumber(z)
  elseif zc == 'Z' then
    p4 = p3 + 1
    z = 0
  else
    p4 = p3
    z = false
  end
  return types.timestamp(y, m, d, h, i, s, f, z), ssub(line, p4+1)
end

local function parsescalar(line, lines, indent)
  line = ltrim(line)
  line = gsub(line, '%s*#.*$', '')

  if line == '' or line == '~' then
    return null
  end

  local ts, _ = parsetimestamp(line)
  if ts then
    return ts
  end

  local s, _ = parsestring(line)
  if s and s ~= line then
    return s
  end

    -- Special cases
  if sfind('\'"!$', ssub(line, 1, 1), 1, true) then
    error('unsupported line: '..line)
  end

  if startswithline(line, '{}') then
    return {}
  end
  if startswithline(line, '[]') then
    return {}
  end

  if startswith(line, '{') or startswith(line, '[') then
    return parseflowstyle(line, lines)
  end

  if startswith(line, '|') or startswith(line, '>') then
    return parseblockstylestring(line, lines, indent)
  end

  -- Regular unquoted string
  local v = line
  if v == 'null' or v == 'Null' or v == 'NULL'then
    return null
  elseif v == 'true' or v == 'True' or v == 'TRUE' then
    return true
  elseif v == 'false' or v == 'False' or v == 'FALSE' then
    return false
  elseif v == '.inf' or v == '.Inf' or v == '.INF' then
    return math.huge
  elseif v == '+.inf' or v == '+.Inf' or v == '+.INF' then
    return math.huge
  elseif v == '-.inf' or v == '-.Inf' or v == '-.INF' then
    return -math.huge
  elseif v == '.nan' or v == '.NaN' or v == '.NAN' then
    return 0 / 0
  elseif sfind(v, '^[%+%-]?[0-9]+$') or sfind(v, '^[%+%-]?[0-9]+%.$')then
    return tonumber(v)  -- : int
  elseif sfind(v, '^[%+%-]?[0-9]+%.[0-9]+$') then
    return tonumber(v)
  end
  return v
end

local parsemap;  -- : func

local function parseseq(line, lines, indent)
  local seq = setmetatable({}, types.seq)
  if line ~= '' then
    error()
  end
  while #lines > 0 do
    -- Check for a new document
    line = lines[1]
    if startswith(line, '---') then
      while #lines > 0 and not startswith(lines, '---') do
        tremove(lines, 1)
      end
      return seq
    end

    -- Check the indent level
    local level = countindent(line)
    if level < indent then
      return seq
    elseif level > indent then
      error("found bad indenting in line: ".. line)
    end

    local i, j = sfind(line, '%-%s+')
    if not i then
      i, j = sfind(line, '%-$')
      if not i then
        return seq
      end
    end
    local rest = ssub(line, j+1)

    if sfind(rest, '^[^\'\"%s]*:') then
      -- Inline nested hash
      local indent2 = j
      lines[1] = string.rep(' ', indent2)..rest
      tinsert(seq, parsemap('', lines, indent2))
    elseif isemptyline(rest) then
      tremove(lines, 1)
      if #lines == 0 then
        tinsert(seq, null)
        return seq
      end
      if sfind(lines[1], '^%s*%-') then
        local nextline = lines[1]
        local indent2 = countindent(nextline)
        if indent2 == indent then
          -- Null seqay entry
          tinsert(seq, null)
        else
          tinsert(seq, parseseq('', lines, indent2))
        end
      else
        -- - # comment
        --   key: value
        local nextline = lines[1]
        local indent2 = countindent(nextline)
        tinsert(seq, parsemap('', lines, indent2))
      end
    elseif rest then
      -- Array entry with a value
      tremove(lines, 1)
      tinsert(seq, parsescalar(rest, lines))
    end
  end
  return seq
end

local function parseset(line, lines, indent)
  if not isemptyline(line) then
    error('not seq line: '..line)
  end
  local set = setmetatable({}, types.set)
  while #lines > 0 do
    -- Check for a new document
    line = lines[1]
    if startswith(line, '---') then
      while #lines > 0 and not startswith(lines, '---') do
        tremove(lines, 1)
      end
      return set
    end

    -- Check the indent level
    local level = countindent(line)
    if level < indent then
      return set
    elseif level > indent then
      error("found bad indenting in line: ".. line)
    end

    local i, j = sfind(line, '%?%s+')
    if not i then
      i, j = sfind(line, '%?$')
      if not i then
        return set
      end
    end
    local rest = ssub(line, j+1)

    if sfind(rest, '^[^\'\"%s]*:') then
      -- Inline nested hash
      local indent2 = j
      lines[1] = string.rep(' ', indent2)..rest
      set[parsemap('', lines, indent2)] = true
    elseif sfind(rest, '^%s+$') then
      tremove(lines, 1)
      if #lines == 0 then
        tinsert(set, null)
        return set
      end
      if sfind(lines[1], '^%s*%?') then
        local indent2 = countindent(lines[1])
        if indent2 == indent then
          -- Null array entry
          set[null] = true
        else
          set[parseseq('', lines, indent2)] = true
        end
      end

    elseif rest then
      tremove(lines, 1)
      set[parsescalar(rest, lines)] = true
    else
      error("failed to classify line: "..line)
    end
  end
  return set
end

function parsemap(line, lines, indent)
  if not isemptyline(line) then
    error('not map line: '..line)
  end
  local map = setmetatable({}, types.map)
  while #lines > 0 do
    -- Check for a new document
    line = lines[1]
    if startswith(line, '---') then
      while #lines > 0 and not startswith(lines, '---') do
        tremove(lines, 1)
      end
      return map
    end

    -- Check the indent level
    local level, _ = countindent(line)
    if level < indent then
      return map
    elseif level > indent then
      error("found bad indenting in line: ".. line)
    end

    -- Find the key
    local key
    local s, rest = parsestring(line)

    -- Quoted keys
    if s and startswith(rest, ':') then
      local sc = parsescalar(s, {}, 0)
      if sc and type(sc) ~= 'string' then
        key = sc
      else
        key = s
      end
      line = ssub(rest, 2)
    else
      error("failed to classify line: "..line)
    end

    if map[key] ~= nil then
      -- print("found a duplicate key '"..key.."' in line: "..line)
      local suffix = 1
      while map[key..'__'..suffix] do
        suffix = suffix + 1
      end
      key = key ..'_'..suffix
    end

    line = ltrim(line)

    if ssub(line, 1, 1) == '!' then
      -- ignore type
      local rh = ltrim(ssub(line, 3))
      local typename = smatch(rh, '^!?[^%s]+')
      line = ltrim(ssub(rh, #typename+1))
    end

    if not isemptyline(line) then
      tremove(lines, 1)
      line = ltrim(line)
      map[key] = parsescalar(line, lines, indent)
    else
      -- An indent
      tremove(lines, 1)
      if #lines == 0 then
        map[key] = null
        return map;
      end
      if sfind(lines[1], '^%s*%-') then
        local indent2 = countindent(lines[1])
        map[key] = parseseq('', lines, indent2)
      elseif sfind(lines[1], '^%s*%?') then
        local indent2 = countindent(lines[1])
        map[key] = parseset('', lines, indent2)
      else
        local indent2 = countindent(lines[1])
        if indent >= indent2 then
          -- Null hash entry
          map[key] = null
        else
          map[key] = parsemap('', lines, indent2)
        end
      end
    end
  end
  return map
end


-- : (list<str>)->dict
local function parsedocuments(lines)
  lines = select(lines, function(s) return not isemptyline(s) end)

  if sfind(lines[1], '^%%YAML') then tremove(lines, 1) end

  local root = {}
  local in_document = false
  while #lines > 0 do
    local line = lines[1]
    -- Do we have a document header?
    local docright;
    if sfind(line, '^%-%-%-') then
      -- Handle scalar documents
      docright = ssub(line, 4)
      tremove(lines, 1)
      in_document = true
    end
    if docright then
      if (not sfind(docright, '^%s+$') and
          not sfind(docright, '^%s+#')) then
        tinsert(root, parsescalar(docright, lines))
      end
    elseif #lines == 0 or startswith(line, '---') then
      -- A naked document
      tinsert(root, null)
      while #lines > 0 and not sfind(lines[1], '---') do
        tremove(lines, 1)
      end
      in_document = false
    -- XXX The final '-+$' is to look for -- which ends up being an
    -- error later.
    elseif not in_document and #root > 0 then
      -- only the first document can be explicit
      error('parse error: '..line)
    elseif sfind(line, '^%s*%-') then
      -- An array at the root
      tinsert(root, parseseq('', lines, 0))
    elseif sfind(line, '^%s*[^%s]') then
      -- A hash at the root
      local level = countindent(line)
      tinsert(root, parsemap('', lines, level))
    else
      -- Shouldn't get here.  @lines have whitespace-only lines
      -- stripped, and previous match is a line with any
      -- non-whitespace.  So this clause should only be reachable via
      -- a perlbug where \s is not symmetric with \S

      -- uncoverable statement
      error('parse error: '..line)
    end
  end
  if #root > 1 and Null.isnull(root[1]) then
    tremove(root, 1)
    return root
  end
  return root
end


local function parse(source)
  local lines = {}
  for line in string.gmatch(source .. '\n', '(.-)\r?\n') do
    tinsert(lines, line)
  end

  local docs = parsedocuments(lines)
  if #docs == 1 then
    return docs[1]
  end

  return docs
end

return {
  version = 0.1,
  parse = parse,
}
