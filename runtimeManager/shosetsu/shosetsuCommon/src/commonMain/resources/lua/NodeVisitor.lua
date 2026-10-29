return function(head, tail, elems_only)
    head = head or function()end
    tail = tail or function()end
    elems_only = elems_only == nil or elems_only
    return _NodeVisitor(head, tail, elems_only)
end
