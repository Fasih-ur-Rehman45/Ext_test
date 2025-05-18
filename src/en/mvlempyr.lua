-- {"id":620191,"ver":"1.0.25","libVer":"1.0.0","author":""}
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

--- Cache for all novels
local allNovels = nil
local loadedPages = 0 -- Track loaded pages
local totalPages = nil -- Store total pages if detected
local pageQueryId = "c5c66f03" -- Default pagination parameter
--- Load novels from advance-search with paginated loading
local function loadAllNovels(startPage, endPage)
    if not allNovels then
        allNovels = { novels = {}, seenLinks = {} }
    end
    local novels = allNovels.novels
    local seenLinks = allNovels.seenLinks
    -- Ensure valid page range
    startPage = startPage or 1
    endPage = endPage or startPage + 19 -- Default to 20 pages per batch
    if startPage < 1 then startPage = 1 end
    if endPage < startPage then endPage = startPage end
    for page = startPage, endPage do
        if loadedPages >= page then
            -- Skip already loaded pages
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
            if seenLinks[link] then
                goto inner_continue
            end
            seenLinks[link] = true
            local image = v:selectFirst("img")
            image = image and image:attr("src") or imageURL
            table.insert(novels, {
                title = name,
                link = shrinkURL(link),
                imageURL = image
            })
            newNovelsFound = true
            ::inner_continue::
        end
        -- Stop if no new novels are found
        if not newNovelsFound then
            return novels
        end
        ::continue::
    end
    return novels
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
    -- Load the first 20 pages (300 novels)
    local pageBatchSize = 20
    local currentStartPage = 1
    local novels = loadAllNovels(currentStartPage, currentStartPage + pageBatchSize - 1)
    local filtered = {}
    -- Filter novels based on search term
    for _, novel in ipairs(novels) do
        local title = novel.title or ""
        title = title:lower()
        if title:find(query, 1, true) then
            table.insert(filtered, Novel {
                title = novel.title,
                link = novel.link,
                imageURL = novel.imageURL
            })
        end
    end
    -- Continue loading batches of 20 pages until all pages are loaded
    while true do
        -- Check if there are more pages to load
        local nextPageExists = true
        local lastPageDoc = GETDocument(
            (baseURL .. "advance-search" .. (loadedPages > 1 and "?" .. pageQueryId .. "_page=" .. loadedPages or "")):gsub("(%w+://[^/]+)%.(com|net)(/|$)", "%1.space%3"),
            { timeout = 60000, javascript = true }
        )
        local nextPageLink = lastPageDoc:selectFirst("a.w-pagination-next.next")
        if not nextPageLink or not nextPageLink:attr("href") then
            nextPageExists = false
        end
        if not nextPageExists then
            break
        end
        -- Load the next batch of 20 pages
        currentStartPage = currentStartPage + pageBatchSize
        novels = loadAllNovels(currentStartPage, currentStartPage + pageBatchSize - 1)   
        -- Update filtered list with new novels
        for _, novel in ipairs(novels) do
            local title = novel.title or ""
            title = title:lower()
            if title:find(query, 1, true) then
                table.insert(filtered, Novel {
                    title = novel.title,
                    link = novel.link,
                    imageURL = novel.imageURL
                })
            end
        end
    end
    -- Paginate results
    local page = data[PAGE] or 1
    local perPage = 20
    local startIndex = (page - 1) * perPage + 1
    local endIndex = math.min(startIndex + perPage - 1, #filtered)
    
    -- Adjust for out-of-bounds pages
    if startIndex > #filtered and #filtered > 0 then
        startIndex = 1
        endIndex = math.min(perPage, #filtered)
        page = 1
    elseif startIndex > #filtered then
        return {}
    end
    
    local paged = {}
    for i = startIndex, endIndex do
        if filtered[i] then
            table.insert(paged, filtered[i])
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