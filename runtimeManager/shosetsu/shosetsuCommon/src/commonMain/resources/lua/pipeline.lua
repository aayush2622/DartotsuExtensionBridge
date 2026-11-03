-- Utility to make code in extensions read properly, linearly in order of execution.
-- Inspired by many languages' pipeline operators.

-- The code may get vertically higher, but readability improves by a lot

--[[
Example comparison usage in getPassage, before using pipeline:
    return table.concat(map(filter(GETDocument(expandURL(url)):selectFirst(".selector"):children(),
            function(v)
				return v:tagName() ~= "script"
			end), text), "\n")

Using pipeline:
	return pipeline
			(GETDocument(expandURL(url)):selectFirst(".selector"):children())
			(filter, function(v)
				return v:tagName() ~= "script"
			end)
			(map, text)
			(table.concat, "\n")
			()
]]

-- A call to pipeline by the user starts the pipeline with data `obj`
local function pipeline(obj)
    -- Calls to the returned function start with the function `f` to apply onto the data,
    -- all further arguments are added after the data to the `f` function call
    return function(f, ...)
        if not f then
            -- A call with no arguments returns the data, ending the pipeline
            return obj
        else
            -- A call with arguments applies `f` on the data and continues the pipeline
            return pipeline(f(obj, ...))
        end
    end
end

return pipeline