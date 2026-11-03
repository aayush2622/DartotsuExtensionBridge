return function(o, f)
    for i=1, o:size() do
        local v = o:get(i-1)
        if f(v) then return v end
    end
    return nil
end
