local newproxy = newproxy
local getmetatable = getmetatable
local setmetatable = setmetatable
local select = select

local _M = {
    version = 0.1,
    new    = require("table.new"),
    clear  = require("table.clear"),
    nkeys  = require("table.nkeys"),
    insert = table.insert,
    concat = table.concat,
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


return _M
