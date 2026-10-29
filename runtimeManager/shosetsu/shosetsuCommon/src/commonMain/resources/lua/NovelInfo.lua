return function(t)
    local o = _NovelInfo()
    if not t then return o end

    local fields = {
        ["title"] = o.setTitle,
        ["alternativeTitles"] = o.setAlternativeTitles,
        ["link"] = o.setLink,
        ["imageURL"] = o.setImageURL,
        ["language"] = o.setLanguage,
        ["description"] = o.setDescription,
        ["status"] = o.setStatus,
        ["tags"] = o.setTags,
        ["genres"] = o.setGenres,
        ["authors"] = o.setAuthors,
        ["artists"] = o.setArtists,
        ["chapters"] = o.setChapters,
        ["chapterCount"] = o.setChapterCount,
        ["wordCount"] = o.setWordCount,
        ["commentCount"] = o.setCommentCount,
        ["viewCount"] = o.setViewCount,
        ["favoriteCount"] = o.setFavoriteCount,
    }

    for k, v in pairs(t) do
        if fields[k] then fields[k](o, v) end
    end

    return o
end
