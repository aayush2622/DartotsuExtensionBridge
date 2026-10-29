-- o is a table or java object with size and get methods (usually Elements or ArrayList)
-- f is a function mapping every value from that table or arraylist to the value it will become in the resulting table
return function(o, f)
    local t = {} -- result
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