-- {"id":620191,"ver":"1.0.15","libVer":"1.0.0","author":""}
local json = Require("dkjson")
local bigint = Require("bigint")

--- Identification number of the extension.
local id = 620191

local name = "MVLEMPYR"

--- Base URL of the extension.
local baseURL = "https://www.mvlempyr.com/"

--- URL of the logo.
local imageURL = "https://assets.mvlempyr.com/images/asset/LogoMage.webp"

--- URL handling functions.
local function shrinkURL(url, _)
    -- Match .com or .net at domain boundary, replace with .space
    return url:gsub("(%w+://[^/]+)%.(com|net)(/|$)", "%1.space%3")
end

local function expandURL(url, _)
    return url:gsub("(%w+://[^/]+)%.(space)(/|$)", "%1.com%3")
end

local startIndex = 1

--- Cache for all novels
local allNovels = nil
local loadedPages = 0 -- Track loaded pages
local totalPages = nil -- Store total pages if detected
local pageQueryId = "c5c66f03" -- Default pagination parameter

--- Check for Cloudflare captcha
local function checkCaptcha(doc)
    local title = doc:selectFirst("title"):text()
    if title == "Attention Required! | Cloudflare" or title == "Just a moment..." then
        error("Captcha error, please open in webview")
    end
end

--- Load novels from advance-search, with lazy loading
local function loadAllNovels(pageToLoad)
    if not allNovels then
        allNovels = {}
    end
    local seenLinks = allNovels.seenLinks or {}
    if not pageToLoad then
        pageToLoad = 1
    end

    -- Load only if not already loaded up to the requested page
    while loadedPages < pageToLoad do
        loadedPages = loadedPages + 1
        local url = (baseURL .. "advance-search" .. (loadedPages > 1 and "?" .. pageQueryId .. "_page=" .. loadedPages or "")):gsub("(%w+://[^/]+)%.(com|net)(/|$)", "%1.space%3")
        local document = GETDocument(url, {
            timeout = 30000,  -- Reduced to 30 seconds for faster initial load
            javascript = true
        })
        checkCaptcha(document)

        -- Detect total pages on first load
        if loadedPages == 1 then
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
                goto continue
            end
            name = name:text()
            local linkElement = v:selectFirst("a")
            if not linkElement then
                goto continue
            end
            local link = linkElement:attr("href")
            if not link or link == "" then
                goto continue
            end
            link = link:gsub("^/", "")
            link = baseURL .. link
            if seenLinks[link] then
                goto continue
            end
            seenLinks[link] = true
            local image = v:selectFirst("img")
            image = image and image:attr("src") or imageURL
            table.insert(allNovels, {
                title = name,
                link = shrinkURL(link),
                imageURL = image
            })
            newNovelsFound = true
            ::continue::
        end

        -- Stop if no new novels are found or all pages are loaded
        if not newNovelsFound or (totalPages and loadedPages >= totalPages) then
            allNovels.seenLinks = seenLinks
            return allNovels
        end
    end

    allNovels.seenLinks = seenLinks
    return allNovels
end

--- @param chapterURL string The chapters shrunken URL.
--- @return string String of chapter
local function getPassage(chapterURL)
    local url = expandURL(chapterURL)
    local document = GETDocument(url)
    checkCaptcha(document)
    local htmlElement = document:selectFirst("#chapter")
    if not htmlElement then
        error("Failed to find #chapter element")
    end
    local title = document:selectFirst(".ct-headline.ChapterName .ct-span")
    title = title and title:text() or "Untitled"
    local ht = "<h1>" .. title .. "</h1>"
    return ht .. pageOfElem(htmlElement, true)
end

--- Calculate tag ID from novel code, matching TS convertNovelId
local function calculateTagId(novel_code)
    local t = bigint.new("1999999997")
    local c = bigint.modulus(bigint.new("7"), t);
    local d = tonumber(novel_code);
    local u = bigint.new(1);
    while d > 0 do
        if (d % 2) == 1 then
            u = bigint.modulus((u * c), t)
        end
        c = bigint.modulus((c * c), t);
        d = math.floor(d/2);
    end
    return bigint.unserialize(u, "string")
end

--- Load info on a novel.
--- @param novelURL string shrunken novel url.
--- @return NovelInfo
local function parseNovel(novelURL)
    local url = expandURL(novelURL)
    local document = GETDocument(url)
    checkCaptcha(document)
    local desc = ""
    map(document:select(".synopsis p"), function(p)
        desc = desc .. '\n' .. p:text()
    end)
    local img = document:selectFirst("img.novel-image2")
    img = img and img:attr("src") or imageURL
    local code = document:selectFirst("#novel-code")
    if not code then
        error("Failed to find #novel-code element")
    end
    code = code:text()

    local headers = HeadersBuilder():add("Origin", baseURL):build()
    local chapters = {}
    local page = 1
    local chapSite = "https://chap.mvlempyr.space/"
    repeat
        local chapter_url = chapSite .. "wp-json/wp/v2/posts?tags=" .. calculateTagId(code) .. "&per_page=500&page=" .. page
        local chapter_data = json.GET(chapter_url, headers)
        if not chapter_data then
            break
        end
        for i, v in ipairs(chapter_data) do
            local chapter = NovelChapter {
                order = v.acf.chapter_number,
                title = v.acf.ch_name or "Untitled Chapter",
                link = shrinkURL(baseURL .. "chapter/" .. v.acf.novel_code .. "-" .. v.acf.chapter_number)
            }
            table.insert(chapters, chapter)
        end
        page = page + 1
    until #chapter_data < 500
    -- Reverse chapters to match TS implementation
    local reversedChapters = {}
    for i = 1, #chapters do
        reversedChapters[i] = chapters[#chapters - i + 1]
    end
    return NovelInfo({
        title = document:selectFirst(".novel-title2"):text():gsub("\n", ""),
        imageURL = img,
        description = desc,
        chapters = reversedChapters
    })
end

--- Get listing of novels
local function getListing(data)
    local listing_page_parm = nil
    local url = "https://www.mvlempyr.com/novels" .. (listing_page_parm and (listing_page_parm .. data[PAGE]) or "")
    url = url:gsub("(%w+://[^/]+)%.(com|net)(/|$)", "%1.space%3")
    local document = GETDocument(url)
    checkCaptcha(document)
    if not listing_page_parm then
        local paginationElement = document:selectFirst(".g-tpage a.painationbutton.w--current, .g-tpage a.w-pagination-next")
        if not paginationElement then
            error(document)
        end
        listing_page_parm = paginationElement:attr("href")
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
            title = v:attr("title") or "Untitled",
            link = shrinkURL("https://www.mvlempyr.com/" .. v:attr("href"):gsub("^/", "")),
            imageURL = v:selectFirst("img"):attr("src") or imageURL
        }
    end)
end

--- Search novels, inspired by TS searchNovels
local function search(data)
    local query = data[QUERY]:lower()
    
    -- Load only the necessary pages based on the requested page
    local requestedPage = data[PAGE] or 1
    local novels = loadAllNovels(math.ceil(requestedPage * 20 / 15)) -- Load enough pages to cover the requested results (20 per page)
    local filtered = {}
    
    -- Filter novels based on search term, inspired by TS searchNovels
    for _, novel in ipairs(novels) do
        if novel.title:lower():find(query, 1, true) then
            table.insert(filtered, Novel {
                title = novel.title,
                link = novel.link,
                imageURL = novel.imageURL
            })
        end
    end
    
    -- Paginate results, inspired by TS paginate
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
    
    print("Total Matches: " .. #filtered .. " | Page " .. page .. " Results: " .. #paged)
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