local select = select

local _M = {
    new    = require("table.new"),
    clear  = require("table.clear"),
    nkeys  = require("table.nkeys"),
    insert = table.insert,
    concat = table.concat,
}


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


return _M
