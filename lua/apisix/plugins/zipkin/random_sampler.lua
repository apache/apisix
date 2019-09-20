local _M = {}
local mt = { __index = _M }

function _M.new(conf)
    local sample_ratio = conf.sample_ratio
    assert(type(sample_ratio) == "number" and
        sample_ratio >= 0 and sample_ratio <= 1, "invalid sample_ratio")
    return setmetatable({
        sample_ratio = sample_ratio
	}, mt)
end

function _M.sample(self)
    return math.random() < self.sample_ratio
end


return _M
