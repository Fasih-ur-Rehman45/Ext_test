-- {"id":10255,"ver":"1.0.10","libVer":"1.0.0","author":""}

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
local filters = {
    order = {
        value = "orderBy",
        options = {
            { display = "View", value = "view" },
            { display = "Name", value = "name" },
            { display = "Date", value = "date" },
            { display = "Reader", value = "reader" },
            { display = "Chapter", value = "chapter" }
        }
    },
    sort = {
        value = "order",
        options = {
            { display = "Descending", value = "descending" },
            { display = "Ascending", value = "ascending" }
        }
    },
    status = {
        value = "filter",
        options = {
            { display = "All", value = "all" },
            { display = "Ongoing", value = "ongoing" },
            { display = "Completed", value = "completed" }
        }
    }
}

-- Search filters
local searchFilters = {
    DropdownFilter(2, "Order by", map(filters.order.options, function(opt) return opt.display end)),
    DropdownFilter(3, "Sort by", map(filters.sort.options, function(opt) return opt.display end)),
    DropdownFilter(4, "Status", map(filters.status.options, function(opt) return opt.display end))
}

-- Function to get the lowercase value for a filter
local function getFilterValue(filterType, displayText)
    local filterOptions = filters[filterType].options
    for _, opt in ipairs(filterOptions) do
        if opt.display == displayText then
            return opt.value
        end
    end
    return filterOptions[1].value
end

local function buildListingURL(data, page)
    local url = baseURL .. "en/novel-list?"
    
    -- Get filter values from data
    local orderDisplay = data[1] or filters.order.options[1].display
    local sortDisplay = data[2] or filters.sort.options[1].display
    local statusDisplay = data[3] or filters.status.options[1].display
    
    url = url .. filters.order.value .. "=" .. getFilterValue("order", orderDisplay)
    url = url .. "&" .. filters.sort.value .. "=" .. getFilterValue("sort", sortDisplay)
    url = url .. "&" .. filters.status.value .. "=" .. getFilterValue("status", statusDisplay)
    url = url .. "&page=" .. (page or 1)
    return url
end

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