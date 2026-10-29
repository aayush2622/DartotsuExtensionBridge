local statuses = {
    ["PUBLISHING"] = 0,
    ["COMPLETED"] = 1,
    ["PAUSED"] = 2,
    ["UNKNOWN"] = -1
}

return setmetatable({}, {
    __call = function(_, v)
        return _NovelStatus(v)
    end,
    __index = function(self, v)
        if type(v) ~= "string" or not statuses[v] then
            error(("Invalid NovelStatus type %s"):format(v), 2)
        end
        return self(statuses[v])
    end
})
