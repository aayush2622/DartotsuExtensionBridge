-- Maps values of an ArrayList or Elements to another ArrayList or Elements, and then to a table (using two functions).
-- Effectively flattens an array, which gives the function its name.

-- Useful when you're working with weird layouts with lists. 
-- Refer to WWVolare or SaikaiScans extensions for example usage.

-- Code duplicated to avoid dependencies
local function map(o, f)
    local t = {}
    if type(o) == "table" then
        for k,v in pairs(o) do
            t[k] = f(v,k)
        end
    else
        for i=0, o:size()-1 do
            t[i+1] = f(o:get(i), i)
        end
    end

    return t
end

local function flatten(o)
    local t, i = {}, 1

    for _,u in pairs(o) do
        for _,v in pairs(u) do
            t[i] = v
            i = i + 1
        end
    end

    return t
end

return function(o, f1, f2)
    local t, j = {}, 0
    return flatten(map( -- flatten (any[][] -> any[])
        map(o, f1), -- map first (any[] -> any[][])
        function(v) -- second map (any[][] -> any[][]) - further processing happens here
            return map(v, f2)
        end)
    )
end
