return function(url, headers, body, cctl)
    headers = headers or DEFAULT_HEADERS()
    cctl = cctl or DEFAULT_CACHE_CONTROL()
    body = body or DEFAULT_BODY()
    return _POST(url, headers, body, cctl)
end
