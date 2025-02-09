-- {"id":10255,"ver":"1.0.9","libVer":"1.0.0","author":""}

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
local ORDER_FILTER_ID = 2
local SORT_FILTER_ID = 4
local STATUS_FILTER_ID = 3


--- Filters configuration.
local orderFilterOptions = {
    { display = "View", value = "view" },
    { display = "Name", value = "name" },
    { display = "Date", value = "date" },  -- Renamed from "Addition Date" to "Date"
    { display = "Reader", value = "reader" },
    { display = "Chapter", value = "chapter" }
}

-- Mapping table for sort filter options
local sortFilterOptions = {
    { display = "Descending", value = "descending" },
    { display = "Ascending", value = "ascending" }
}

-- Mapping table for status filter options
local statusFilterOptions = {
    { display = "All", value = "all" },
    { display = "Ongoing", value = "ongoing" },
    { display = "Completed", value = "completed" }
}

-- Search filters
local searchFilters = {
    DropdownFilter(ORDER_FILTER_ID, "Order by", map(orderFilterOptions, function(opt) return opt.display end)),
    DropdownFilter(SORT_FILTER_ID, "Sort by", map(sortFilterOptions, function(opt) return opt.display end)),
    DropdownFilter(STATUS_FILTER_ID, "Status", map(statusFilterOptions, function(opt) return opt.display end))
}

-- Function to get the lowercase value for a filter
local function getFilterValue(filterOptions, displayText)
    for _, opt in ipairs(filterOptions) do
        if opt.display == displayText then
            return opt.value
        end
    end
    return nil
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
            -- Retrieve filters from the data object
            local orderDisplay = data[ORDER_FILTER_ID] or "View"
            local sortDisplay = data[SORT_FILTER_ID] or "Descending"
            local statusDisplay = data[STATUS_FILTER_ID] or "All"
            -- Convert display text to lowercase values
            local order = getFilterValue(orderFilterOptions, orderDisplay) or "view"
            local sort = getFilterValue(sortFilterOptions, sortDisplay) or "descending"
            local status = getFilterValue(statusFilterOptions, statusDisplay) or "all"
            local page = data[PAGE]
            local url = baseURL .. "en/novel-list?orderBy=" .. order .. "&order=" .. sort .. "&filter=" .. status .. "&page=" .. page
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