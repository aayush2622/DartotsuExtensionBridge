-- o is a table or java object with size and get methods (usually Elements or ArrayList)
-- f is a function mapping every value from that table or object to the boolean that defines whether it is included in the resulting array
return function(o, f)
    local t, j = {}, 0

    if type(o) == "table" then
        for k,v in pairs(o) do
            if f(v, k) then
                j = j + 1
                t[j] = v
            end
        end
    else
        for i=0, o:size()-1 do
            local v = o:get(i)
            if f(v, i) then
                j = j + 1
                t[j] = v
            end
        end
    end

    return t
end
