-- {"id":620191,"ver":"1.0.26","libVer":"1.0.0","author":""}
local json = Require("dkjson")
local bigint = Require("bigint")

--- Identification number of the extension.
local id = 620191

local name = "MVLEMPYR"

---@param v Element
local text = function(v)
    return v:text()
end

local chapterType = ChapterType.HTML

--- Base URL of the extension.
local baseURL = "https://www.mvlempyr.com/"

--- URL of the logo.
local imageURL = "https://assets.mvlempyr.com/images/asset/LogoMage.webp"

--- URL handling functions.
local function shrinkURL(url, _)
    return url
end

local function expandURL(url, _)
    return url
end

local startIndex = 1

--- Cache for matching novels only
local matchingNovels = nil
local loadedPages = 0 -- Track loaded pages
local totalPages = nil -- Store total pages if detected
local pageQueryId = "c5c66f03" -- Default pagination parameter
local queryCache = {} -- Cache for query results

--- Clear the novels cache
local function clearNovelsCache()
    matchingNovels = nil
    loadedPages = 0
    totalPages = nil
end

--- Load novels from advance-search with paginated loading
--- Returns novels, whether any matches were found, and the next page link
local function loadAllNovels(startPage, endPage, query)
    query = query:lower()
    local novels = {} -- Temporary list for this batch
    local seenLinks = {} -- Temporary deduplication for this batch
    -- Ensure valid page range
    startPage = startPage or 1
    endPage = endPage or startPage + 19 -- Default to 20 pages per batch
    if startPage < 1 then startPage = 1 end
    if endPage < startPage then endPage = startPage end
    
    local lastNextPageLink = nil -- Store the last "Next Page" link
    local hasMatches = false -- Track if any novels match the query in this batch
    
    for page = startPage, endPage do
        if loadedPages >= page then
            goto continue
        end
        loadedPages = loadedPages + 1
        local url = (baseURL .. "advance-search" .. (page > 1 and "?" .. pageQueryId .. "_page=" .. page or "")):gsub("(%w+://[^/]+)%.(com|net)(/|$)", "%1.space%3")
        local document = GETDocument(url, {
            timeout = 60000,  -- 60 seconds timeout
            javascript = true
        })
        -- Detect total pages on first load
        if page == 1 then
            local totalTextElement = document:selectFirst(".w-page-count.hide")
            local totalText = totalTextElement and totalTextElement:text() or nil
            if totalText then
                local _, _, current, total = totalText:match("Showing (%d+) out of (%d+) novels")
                total = tonumber(total) or 0
                if total > 0 then
                    totalPages = math.ceil(total / 15)
                end
            end
            local nextPageLink = document:selectFirst("a.w-pagination-next.next")
            if nextPageLink and nextPageLink:attr("href") then
                local href = nextPageLink:attr("href")
                pageQueryId = href:match("%?([^=]+)_page=") or pageQueryId
            end
        end
        -- Check for "Next Page" link on the current page
        local nextPageLink = document:selectFirst("a.w-pagination-next.next")
        if nextPageLink and nextPageLink:attr("href") then
            lastNextPageLink = nextPageLink:attr("href")
        else
            lastNextPageLink = nil
        end
        -- Parse novels on the current page
        local elements = document:select(".novelcolumn")
        local newNovelsFound = false
        for i = 0, elements:size() - 1 do
            local v = elements:get(i)
            local name = v:selectFirst("h2[fs-cmsfilter-field=\"name\"]")
            if not name then
                goto inner_continue
            end
            name = name:text()
            local linkElement = v:selectFirst("a")
            if not linkElement then
                goto inner_continue
            end
            local link = linkElement:attr("href")
            if not link or link == "" then
                goto inner_continue
            end
            link = link:gsub("^/", "")
            link = baseURL .. link
            local uniqueKey = link .. "|" .. name
            if seenLinks[uniqueKey] then
                goto inner_continue
            end
            seenLinks[uniqueKey] = true
            local image = v:selectFirst("img")
            image = image and image:attr("src") or imageURL
            local novel = {
                title = name,
                link = shrinkURL(link),
                imageURL = image
            }
            table.insert(novels, novel)
            -- Check if this novel matches the query
            local title = name:lower()
            if title:find(query, 1, true) then
                hasMatches = true
            end
            newNovelsFound = true
            ::inner_continue::
        end
        if not newNovelsFound then
            return novels, hasMatches, lastNextPageLink
        end
        ::continue::
    end
    return novels, hasMatches, lastNextPageLink
end

--- @param chapterURL string The chapters shrunken URL.
--- @return string String of chapter
local function getPassage(chapterURL)
    -- Thanks to bigr4nd for figuring out that somehow .space domain bypasses cloudflare
    local url = expandURL(chapterURL):gsub("(%w+://[^/]+)%.net", "%1.space")
    --- Chapter page, extract info from it.
    local document = GETDocument(url)
    local htmlElement = document:selectFirst("#chapter")
    return pageOfElem(htmlElement, true)
end

--- Calculate tag ID from novel code, matching TS convertNovelId
local function calculateTagId(novel_code)
    local t = bigint.new("1999999997")
    local c = bigint.modulus(bigint.new("7"), t)
    local d = tonumber(novel_code)
    local u = bigint.new(1)
    while d > 0 do
        if (d % 2) == 1 then
            u = bigint.modulus((u * c), t)
        end
        c = bigint.modulus((c * c), t)
        d = math.floor(d/2)
    end
    return bigint.unserialize(u, "string")
end

--- Load info on a novel.
--- @param novelURL string shrunken novel url.
--- @return NovelInfo
local function parseNovel(novelURL)
    local url = expandURL(novelURL)
    local document = GETDocument(url)
    local desc = ""
    map(document:select(".synopsis p"), function(p)
        desc = desc .. '\n' .. p:text()
    end)
    local img = document:selectFirst("img.novel-image2")
    img = img and img:attr("src") or imageURL
    local novel_code = document:selectFirst("#novel-code"):text()
    local headers = HeadersBuilder():add("Origin", "https://www.mvlempyr.com"):build()
    local chapters = {}
    local page = 1
    repeat
        local chapter_data = json.GET("https://chap.mvlempyr.space/wp-json/wp/v2/posts?tags=" .. calculateTagId(novel_code) .. "&per_page=500&page=" .. page, headers)
        for i, v in next, chapter_data do
            table.insert(chapters, NovelChapter {
                order = v.acf.chapter_number,
                title = v.acf.ch_name,
                link = shrinkURL(v.link)
            })
        end
        page = page + 1
    until #chapter_data < 500
    return NovelInfo({
        title = document:selectFirst(".novel-title2"):text():gsub("\n" ,""),
        imageURL = img,
        description = desc,
        chapters = chapters
    })
end

local listing_page_parm
local function getListing(data)
    local document = GETDocument("https://www.mvlempyr.com/novels" .. (listing_page_parm and (listing_page_parm .. data[PAGE]) or ""))
    if not listing_page_parm then
        listing_page_parm = document:selectFirst(".g-tpage a.painationbutton.w--current, .g-tpage a.w-pagination-next")
        if not listing_page_parm then
            error(document)
        end
        listing_page_parm = listing_page_parm:attr("href")
        if not listing_page_parm then
            error("Failed to find listing href")
        end
        listing_page_parm = listing_page_parm:match("%?[^=]+=")
        if not listing_page_parm then
            error("Failed to find listing match")
        end
    end
    return map(document:select(".g-tpage div.searchlist[role=\"listitem\"] .novelcolumn .novelcolumimage a"), function(v)
        return Novel {
            title = v:attr("title"),
            link = "https://www.mvlempyr.com/" .. v:attr("href"),
            imageURL = v:selectFirst("img"):attr("src")
        }
    end)
end

--- Search novels, inspired by TS searchNovels
local function search(data)
    local query = data[QUERY] or ""
    query = query:lower()
    local page = data[PAGE] or 1
    
    -- Check if we can reuse cached results for this query
    if queryCache[query] then
        matchingNovels = queryCache[query]
    else
        -- Clear cache for a fresh search
        clearNovelsCache()
        -- Initialize matching novels list
        if not matchingNovels then
            matchingNovels = {}
        end
        local seenFiltered = {} -- Prevent duplicates in filtered results
        -- Load pages in batches
        local pageBatchSize = 20
        local currentStartPage = 1
        
        -- Continue loading batches until all pages are processed
        while true do
            local novels, hasMatches, nextPageLink = loadAllNovels(currentStartPage, currentStartPage + pageBatchSize - 1, query)
            -- If there are matches in this batch, filter and add to matchingNovels
            if hasMatches then
                for _, novel in ipairs(novels) do
                    local title = novel.title:lower()
                    if title:find(query, 1, true) then
                        local uniqueKey = novel.link .. "|" .. novel.title
                        if not seenFiltered[uniqueKey] then
                            seenFiltered[uniqueKey] = true
                            table.insert(matchingNovels, Novel {
                                title = novel.title,
                                link = novel.link,
                                imageURL = novel.imageURL
                            })
                        end
                    end
                end
            end
            -- Stop if there are no more pages to load
            if not nextPageLink then
                break
            end
            -- Move to the next batch
            currentStartPage = currentStartPage + pageBatchSize
        end
        
        -- Cache the results for this query
        queryCache[query] = matchingNovels
    end
    
    -- Paginate results
    local perPage = 20
    local startIndex = (page - 1) * perPage + 1
    local endIndex = math.min(startIndex + perPage - 1, #matchingNovels)
    
    -- Return empty result for out-of-bounds pages
    if startIndex > #matchingNovels then
        return {}
    end
    
    local paged = {}
    for i = startIndex, endIndex do
        if matchingNovels[i] then
            table.insert(paged, matchingNovels[i])
        end
    end
    
    return paged
end

-- Return all properties in a lua table.
return {
    id = id,
    name = name,
    baseURL = baseURL,
    listings = {
        Listing("Default", true, getListing)
    },
    getPassage = getPassage,
    parseNovel = parseNovel,
    shrinkURL = shrinkURL,
    expandURL = expandURL,
    hasSearch = true,
    isSearchIncrementing = true,
    hasCloudFlare = true,
    search = search,
    imageURL = imageURL,
    chapterType = chapterType,
    startIndex = startIndex,
}