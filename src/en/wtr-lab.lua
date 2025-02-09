-- {"id":10255,"ver":"1.0.11","libVer":"1.0.0","author":""}

local json = Require("dkjson")

--- Identification number of the extension.
local id = 10255  -- Update with your extension ID

--- Name of extension to display to the user.
local name = "WTR-LAB"

--- Base URL of the extension.
local baseURL = "https://wtr-lab.com/"

--- URL of the logo.
local imageURL = "https://i.imgur.com/ObQtFVW.png"  -- Update correct path

--- Cloudflare protection status.
local hasCloudFlare = false

--- Search configuration.
local hasSearch = true
local isSearchIncrementing = true


--- Filters configuration.
local FILTER_IDS = {
    ORDER = 2,
    SORT = 3,
    STATUS = 4
}

local filters = {
    [FILTER_IDS.ORDER] = {
        param = "orderBy",
        options = {
            {display = "View", value = "view"},
            {display = "Name", value = "name"},
            {display = "Date", value = "date"},
            {display = "Reader", value = "reader"},
            {display = "Chapter", value = "chapter"}
        }
    },
    [FILTER_IDS.SORT] = {
        param = "order",
        options = {
            {display = "Descending", value = "desc"},
            {display = "Ascending", value = "asc"}
        }
    },
    [FILTER_IDS.STATUS] = {
        param = "filter",
        options = {
            {display = "All", value = "all"},
            {display = "Ongoing", value = "ongoing"},
            {display = "Completed", value = "completed"}
        }
    }
}

-- Search filters
local searchFilters = {
    DropdownFilter(
        FILTER_IDS.ORDER,
        "Order by",
        map(filters[FILTER_IDS.ORDER].options, function(opt) return opt.display end)
    ),
    DropdownFilter(
        FILTER_IDS.SORT,
        "Sort by",
        map(filters[FILTER_IDS.SORT].options, function(opt) return opt.display end)
    ),
    DropdownFilter(
        FILTER_IDS.STATUS,
        "Status",
        map(filters[FILTER_IDS.STATUS].options, function(opt) return opt.display end)
    )
}

local function findValue(options, display)
    for _, opt in ipairs(options) do
        if opt.display == display then
            return opt.value
        end
    end
    return nil
end

local function buildListingURL(data)
    local params = {}
    
    -- Add all active filters
    for filterId, filterConfig in pairs(filters) do
        local selectedDisplay = data[filterId]
        if selectedDisplay then
            local value = findValue(filterConfig.options, selectedDisplay)
            if value then
                table.insert(params, filterConfig.param .. "=" .. value)
            end
        end
    end
    
    -- Add pagination
    table.insert(params, "page=" .. (data[PAGE] or 1))
    return baseURL .. "en/novel-list?" .. table.concat(params, "&")
end


local listings = {
    Listing("Popular Novels", true, function(data)
        local url = buildListingURL(data)
        local doc = GETDocument(url)
        return map(doc:select(".serie-item"), function(el)
            return Novel {
                title = el:select(".title-wrap a"):text(),
                link = shrinkURL(el:select("a"):attr("href"), KEY_NOVEL_URL),
                imageURL = el:select("img"):attr("src")
            }
        end)
    end)
}
--- URL handling functions.
local function shrinkURL(url, type)
    return url:gsub(baseURL, ""):gsub("^en", "")
end

local function expandURL(url, type)
    url = url:gsub("^/", "")
    return baseURL .. url
end

--- Chapter content extraction.
local function getPassage(chapterURL)
    local url = expandURL(chapterURL, KEY_CHAPTER_URL)
    local doc = GETDocument(url)
    local script = doc:selectFirst("script#__NEXT_DATA__"):html()
    local data = json.decode(script)
    local content = data.props.pageProps.serie.chapter_data.data.body
    local html = table.concat(map(content, function(v) return "<p>" .. v .. "</p>" end))
    return html
end

--- Novel parsing function.
local function parseNovel(novelURL)
    local url = expandURL(novelURL, KEY_NOVEL_URL)
    local doc = GETDocument(url)
    local script = doc:selectFirst("#__NEXT_DATA__"):html()
    local data = json.decode(script)
    local serie = data.props.pageProps.serie

    local novelInfo = NovelInfo {
        title = doc:selectFirst("h1.text-uppercase"):text(),
        imageURL = doc:selectFirst(".img-wrap img"):attr("src"),
        description = doc:selectFirst(".lead"):text(),
        authors = {doc:select("td:matches(^Author$) + td a"):text()},
        status = ({
            Ongoing = NovelStatus.PUBLISHING,
            Completed = NovelStatus.COMPLETED,
        })[doc:selectFirst("td:matches(^Status$) + td"):text()],
    }

    local chapters = {}
    for i, ch in ipairs(serie.chapters) do
        chapters[#chapters+1] = NovelChapter {
            title = ch.title,
            link = "serie-" .. serie.serie_data.raw_id .. "/" .. serie.serie_data.slug .. "/chapter-" .. ch.order,
            order = i
        }
    end
    novelInfo:setChapters(chapters)
    return novelInfo
end

--- Search function.
local function search(data)
    local query = data[QUERY]
    local res = Request {
        url = baseURL .. "api/search",
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Referer"] = baseURL,
            ["Origin"] = baseURL
        },
        body = json.encode({ text = query })
    }
    
    local results = json.decode(res.body)
    return map(results.data, function(v)
        return Novel {
            title = v.data.title,
            link = "serie-" .. v.raw_id .. "/" .. v.slug,
            imageURL = v.data.image
        }
    end)
end

--- Listings configuration.
    local listings = {
        Listing("Popular Novels", true, function(data)
            local url = buildListingURL(data, data[PAGE])
            local doc = GETDocument(url)
            
            return map(doc:select(".serie-item"), function(el)
                return Novel {
                    title = el:select(".title-wrap a"):text():gsub(el:select(".rawtitle"):text(), ""),
                    link = shrinkURL(el:select("a"):attr("href"), KEY_NOVEL_URL),
                    imageURL = el:select("img"):attr("src")
                }
            end)
        end),
    
  
    Listing("Latest Novels", true, function(data)
        local page = data[PAGE]
        local res = Request {
            url = baseURL .. "api/home/recent",
            method = "POST",
            headers = { ["Content-Type"] = "application/json" },
            body = json.encode({ page = page })
        }
        
        local results = json.decode(res.body)
        return map(results.data, function(v)
            return Novel {
                title = v.serie.data.title,
                link = "serie-" .. v.serie.raw_id .. "/" .. v.serie.slug,
                imageURL = v.serie.data.image
            }
        end)
    end)
}

return {
    id = id,
    name = name,
    baseURL = baseURL,
    imageURL = imageURL,
    listings = listings,
    getPassage = getPassage,
    parseNovel = parseNovel,
    shrinkURL = shrinkURL,
    expandURL = expandURL,
    hasSearch = hasSearch,
    search = search,
    searchFilters = searchFilters,
    chapterType = ChapterType.HTML
}