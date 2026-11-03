-- Flattens a table of tables into a single table
return function(t)
    local n, i = {}, 1

    for _,u in pairs(t) do
        if type(u) == "table" then
            for _,v in pairs(u) do
                n[i] = v
                i = i + 1
            end
        else
            for j=0, u:size()-1 do
                n[i] = u:get(j)
                i = i + 1
            end
        end
    end

    return n
end
