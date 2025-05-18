-- {"id":620191,"ver":"1.0.12","libVer":"1.0.0","author":""}
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

--- Check for Cloudflare captcha
local function checkCaptcha(doc)
    local title = doc:selectFirst("title"):text()
    if title == "Attention Required! | Cloudflare" or title == "Just a moment..." then
        error("Captcha error, please open in webview")
    end
end

--- Load all novels from advance-search, inspired by TS getAllNovels
local function loadAllNovels()
    if allNovels then
        print("Using cached novels: " .. #allNovels)
        return allNovels
    end
    allNovels = {}
    local seenLinks = {}
    local page = 1
    local totalPages = nil -- Will be updated if total novels are found
    local pageQueryId = "c5c66f03" -- Default pagination parameter
    local useNextLink = true -- Flag to use "next page" links if total pages fail

    -- Initial page load
    local url = (baseURL .. "advance-search"):gsub("(%w+://[^/]+)%.(com|net)(/|$)", "%1.space%3")
    print("Fetching novels from: " .. url .. " (page " .. page .. ")")
    local document = GETDocument(url, {
        timeout = 90000,  -- Increased to 90 seconds for better JavaScript rendering
        javascript = true
    })
    checkCaptcha(document)

    -- Try to parse total novels to calculate total pages
    local totalTextElement = document:selectFirst(".w-page-count.hide")
    local totalText = totalTextElement and totalTextElement:text() or nil
    if totalText then
        local _, _, current, total = totalText:match("Showing (%d+) out of (%d+) novels")
        current = tonumber(current) or 0
        total = tonumber(total) or 0
        print("Detected: Showing " .. current .. " out of " .. total .. " novels")
        if total > 0 then
            totalPages = math.ceil(total / 15) -- 15 novels per page
            useNextLink = false -- Use total pages for iteration
        end
    else
        print("Failed to find total novels count, falling back to next page links")
    end

    -- Extract pagination parameter from "next page" link
    local nextPageLink = document:selectFirst("a.w-pagination-next.next")
    if nextPageLink and nextPageLink:attr("href") then
        local href = nextPageLink:attr("href")
        pageQueryId = href:match("%?([^=]+)_page=") or pageQueryId
        print("Pagination parameter: " .. pageQueryId)
    else
        print("No pagination parameter found, using default: " .. pageQueryId)
    end

    while true do
        -- Construct URL for the current page
        url = (baseURL .. "advance-search" .. (page > 1 and "?" .. pageQueryId .. "_page=" .. page or "")):gsub("(%w+://[^/]+)%.(com|net)(/|$)", "%1.space%3")
        print("Fetching novels from: " .. url .. " (page " .. page .. (totalPages and " of " .. totalPages or "") .. ")")
        document = GETDocument(url, {
            timeout = 90000,
            javascript = true
        })
        checkCaptcha(document)

        -- Parse novels on the current page
        local elements = document:select(".novelcolumn")
        local newNovelsFound = false
        for i = 0, elements:size() - 1 do
            local v = elements:get(i)
            local name = v:selectFirst("h2[fs-cmsfilter-field=\"name\"]")
            if not name then
                print("Skipping: No h2 found in novelcolumn")
                goto continue
            end
            name = name:text()
            local linkElement = v:selectFirst("a")
            if not linkElement then
                print("Skipping: No link found for " .. name)
                goto continue
            end
            local link = linkElement:attr("href")
            if not link or link == "" then
                print("Skipping: Empty href for " .. name)
                goto continue
            end
            link = link:gsub("^/", "")
            link = baseURL .. link
            if seenLinks[link] then
                print("Skipping duplicate link: " .. link)
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
            print("Added Novel: " .. name .. " | Link: " .. link)
            newNovelsFound = true
            ::continue::
        end

        -- Stop if no new novels are found
        if not newNovelsFound then
            print("No new novels found on page " .. page .. ", stopping pagination")
            break
        end

        -- Decide whether to continue based on total pages or next page link
        if not useNextLink then
            -- Using total pages
            if page >= totalPages then
                print("Reached total pages (" .. totalPages .. "), stopping pagination")
                break
            end
            page = page + 1
        else
            -- Using next page links
            nextPageLink = document:selectFirst("a.w-pagination-next.next")
            if nextPageLink and nextPageLink:attr("href") then
                url = baseURL .. nextPageLink:attr("href")
                page = page + 1
            else
                print("No next page link found, stopping pagination")
                break
            end
        end
    end

    print("Total Novels Loaded: " .. #allNovels)
    return allNovels
end

--- @param chapterURL string The chapters shrunken URL.
--- @return string String of chapter
local function getPassage(chapterURL)
    local url = expandURL(chapterURL)
    print("Fetching passage from: " .. url)
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
    print("Fetching novel info from: " .. url)
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
        print("Fetching chapters from: " .. chapter_url)
        local chapter_data = json.GET(chapter_url, headers)
        if not chapter_data then
            print("No chapter data returned, stopping pagination")
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
    local url = (baseURL .. "novels" .. (data[PAGE] and "?page=" .. data[PAGE] or "")):gsub("(%w+://[^/]+)%.(com|net)(/|$)", "%1.space%3")
    print("Fetching listing from: " .. url)
    local document = GETDocument(url)
    checkCaptcha(document)
    local elements = document:select(".g-tpage div.searchlist[role=\"listitem\"] .novelcolumn .novelcolumimage a")
    local novels = {}
    for i = 0, elements:size() - 1 do
        local v = elements:get(i)
        table.insert(novels, Novel {
            title = v:attr("title") or "Untitled",
            link = shrinkURL(baseURL .. v:attr("href"):gsub("^/", "")),
            imageURL = v:selectFirst("img"):attr("src") or imageURL
        })
    end
    return novels
end

--- Search novels, inspired by TS searchNovels
local function search(data)
    local query = data[QUERY]:lower()
    print("Search Query: " .. query)
    
    -- Load all novels, inspired by TS getAllNovels
    local novels = loadAllNovels()
    local filtered = {}
    
    -- Filter novels based on search term, inspired by TS searchNovels
    for _, novel in ipairs(novels) do
        if novel.title:lower():find(query, 1, true) then
            print("Matching Novel: " .. novel.title)
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
        print("Adjusting to page 1 due to out-of-bounds page " .. page)
        startIndex = 1
        endIndex = math.min(perPage, #filtered)
        page = 1
    elseif startIndex > #filtered then
        print("No results for page " .. page)
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