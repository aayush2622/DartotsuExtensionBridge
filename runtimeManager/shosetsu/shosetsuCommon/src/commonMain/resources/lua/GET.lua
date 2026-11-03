return function(url, headers, cctl)
    headers = headers or DEFAULT_HEADERS()
    cctl = cctl or DEFAULT_CACHE_CONTROL()
    return _GET(url, headers, cctl)
end
