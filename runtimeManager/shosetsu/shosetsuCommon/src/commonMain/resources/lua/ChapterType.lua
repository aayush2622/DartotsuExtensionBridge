local types = {
    ["STRING"] = 0,
    ["HTML"] = 1,
    ["EPUB"] = 2,
    ["PDF"] = 3,
    ["MARKDOWN"] = 4
}

return setmetatable({}, {
    __call = function(_, v)
        return _ChapterType(v)
    end,
    __index = function(self, v)
        if type(v) ~= "string" or not types[v] then
            error(("Invalid ChapterType type %s"):format(v), 2)
        end
        return self(types[v])
    end
})
