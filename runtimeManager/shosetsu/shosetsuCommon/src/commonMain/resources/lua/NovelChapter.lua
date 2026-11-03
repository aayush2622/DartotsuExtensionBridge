return function(t)
    local o = _NovelChapter()
    if not t then return o end

    local fields = {
        ["release"] = o.setRelease,
        ["title"] = o.setTitle,
        ["link"] = o.setLink,
        ["order"] = o.setOrder,
        ["sourceId"] = o.setSourceId
    }

    for k, v in pairs(t) do
        if fields[k] then fields[k](o, v) end
    end

    return o
end
