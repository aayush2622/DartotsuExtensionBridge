return function(o, f)
    local t, j = {}, 1
    for i=0, o:size()-1 do
        local v = f(o:get(i))
        if v then
            t[j] = v
            j = j + 1
        end
    end
    return t
end
