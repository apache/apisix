local newproxy     = newproxy
local getmetatable = getmetatable
local setmetatable = setmetatable
local select       = select
local new_tab      = require("table.new")
local nkeys        = require("table.nkeys")
local pairs        = pairs
local type         = type


local _M = {
    version = 0.1,
    new     = new_tab,
    clear   = require("table.clear"),
    nkeys   = nkeys,
    insert  = table.insert,
    concat  = table.concat,
    clone   = require("table.clone"),
}


setmetatable(_M, {__index = table})


function _M.insert_tail(tab, ...)
    local idx = #tab
    for i = 1, select('#', ...) do
        idx = idx + 1
        tab[idx] = select(i, ...)
    end

    return idx
end


function _M.set(tab, ...)
    for i = 1, select('#', ...) do
        tab[i] = select(i, ...)
    end
end


-- only work under lua51 or luajit
function _M.setmt__gc(t, mt)
    local prox = newproxy(true)
    getmetatable(prox).__gc = function() mt.__gc(t) end
    t[prox] = true
    return setmetatable(t, mt)
end


local function deepcopy(orig)
    local orig_type = type(orig)
    if orig_type ~= 'table' then
        return orig
    end

    local copy = new_tab(0, nkeys(orig))
    for orig_key, orig_value in pairs(orig) do
        copy[orig_key] = deepcopy(orig_value)
    end

    return copy
end
_M.deepcopy = deepcopy


return _M
