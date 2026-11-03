return function(node, remove_style_attr, custom_style, keep_scripts)
    node = node or error("No element for pageOfElem")
    remove_style_attr = remove_style_attr ~= nil and remove_style_attr
    custom_style = custom_style or ""
    keep_scripts = keep_scripts ~= nil and keep_scripts
    return _PageOfElem(node, remove_style_attr, custom_style, keep_scripts)
end
