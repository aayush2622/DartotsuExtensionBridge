return function(o, f)
    return function(...)
        return f(o, ...)
    end
end