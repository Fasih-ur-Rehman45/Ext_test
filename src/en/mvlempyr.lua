-- {"id":620191,"ver":"1.0.11","libVer":"1.0.0","author":""}

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
    return url:gsub("(%w+://[^/]+)%.(com|net)(/|$)", "%1.space%3")
end

local startIndex = 1

--- Cache for all novels
local allNovels = nil

--- Load all novels from advance-search, inspired by TS getAllNovels
local function loadAllNovels()
    if allNovels then
        print("Using cached novels: " .. #allNovels)
        return allNovels
    end
    allNovels = {}
    local seenLinks = {}
    local url = (baseURL .. "advance-search"):gsub("(%w+://[^/]+)%.(com|net)(/|$)", "%1.space%3")
    print("Fetching novels from: " .. url)
    local document = GETDocument(url)
    local elements = document:select(".novelcolumn")
    local novelElements = {}
    for i = 0, elements:size() - 1 do
        table.insert(novelElements, elements:get(i))
    end
    for _, v in ipairs(novelElements) do
        local name = v:selectFirst(".novelcolumcontent h2")
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
        if not link then
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
        ::continue::
    end
    print("Total Novels Loaded: " .. #allNovels)
    return allNovels
end

--- @param chapterURL string The chapters shrunken URL.
--- @return string Strings @of chapter
local function getPassage(chapterURL)
    local url = (expandURL(chapterURL)):gsub("(%w+://[^/]+)%.(com|net)(/|$)", "%1.space%3")
    print("Fetching passage from: " .. url)
    local document = GETDocument(url)
    local htmlElement = document:selectFirst("#chapter")
    if not htmlElement then
        error("Failed to find #chapter element")
    end
    local title = document:selectFirst(".ct-headline.ChapterName .ct-span")
    title = title and title:text() or "Untitled"
    local ht = "<h1>" .. title .. "</h1>"
    return pageOfElem(htmlElement, true)
end

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
        d = math.floor(d / 2)
    end
    return bigint.unserialize(u, "string")
end

--- Load info on a novel.
--- @param novelURL string shrunken novel url.
--- @return NovelInfo
local function parseNovel(novelURL)
    local url = (expandURL(novelURL)):gsub("(%w+://[^/]+)%.(com|net)(/|$)", "%1.space%3")
    print("Fetching novel info from: " .. url)
    local document = GETDocument(url)
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
    repeat
        local chapter_url = "https://chap.mvlempyr.space/wp-json/wp/v2/posts?tags=" .. calculateTagId(code) .. "&per_page=500&page=" .. page
        print("Fetching chapters from: " .. chapter_url)
        local chapter_data = json.GET(chapter_url, headers)
        for i, v in ipairs(chapter_data) do
            table.insert(chapters, NovelChapter {
                order = v.acf.chapter_number,
                title = v.acf.ch_name,
                link = shrinkURL(v.link)
            })
        end
        page = page + 1
    until #chapter_data < 500
    return NovelInfo({
        title = document:selectFirst(".novel-title2"):text():gsub("\n", ""),
        imageURL = img,
        description = desc,
        chapters = chapters
    })
end

local listing_page_parm
local function getListing(data)
    local url = (baseURL .. "novels" .. (listing_page_parm and (listing_page_parm .. data[PAGE]) or "")):gsub("(%w+://[^/]+)%.(com|net)(/|$)", "%1.space%3")
    print("Fetching listing from: " .. url)
    local document = GETDocument(url)
    if not listing_page_parm then
        listing_page_parm = document:selectFirst(".g-tpage a.painationbutton.w--current, .g-tpage a.w-pagination-next")
        if not listing_page_parm then
            error("Failed to find listing pagination link")
        end
        listing_page_parm = listing_page_parm:attr("href")
        if not listing_page_parm then
            error("Failed to find listing href")
        end
        listing_page_parm = listing_page_parm:match("%?[^=]+=")
        if not listing_page_parm then
            error("Failed to find listing parameter")
        end
    end
    local elements = document:select(".g-tpage div.searchlist[role=\"listitem\"] .novelcolumn .novelcolumimage a")
    local novels = {}
    for i = 0, elements:size() - 1 do
        local v = elements:get(i)
        table.insert(novels, Novel {
            title = v:attr("title"),
            link = shrinkURL(baseURL .. v:attr("href"):gsub("^/", "")),
            imageURL = v:selectFirst("img"):attr("src")
        })
    end
    return novels
end

--- Search novels, inspired by TS searchNovels
local function search(data)
    local query = data[QUERY]:lower()
    print("Search Query: " .. query)
    
    -- Load all novels
    local novels = loadAllNovels()
    local filtered = {}
    
    -- Filter novels based on the search query
    for _, novel in ipairs(novels) do
        local title = novel.title:lower()
        local matches = title:find(query, 1, true)
        print("Checking Novel: " .. novel.title .. " | Contains '" .. query .. "': " .. tostring(matches))
        if matches then
            table.insert(filtered, Novel {
                title = novel.title,
                link = novel.link,
                imageURL = novel.imageURL
            })
        end
    end
    
    -- Pagination logic
    local page = data[PAGE] or 1
    local perPage = 20
    local startIndex = (page - 1) * perPage + 1
    local endIndex = math.min(startIndex + perPage - 1, #filtered)
    
    -- Adjust for out of bounds
    if startIndex > #filtered and #filtered > 0 then
        print("Total Novels Found: " .. #filtered .. " | Page " .. page .. " out of bounds (startIndex: " .. startIndex .. "), returning page 1 results")
        startIndex = 1
        endIndex = math.min(perPage, #filtered)
        page = 1
    elseif startIndex > #filtered then
        print("Total Novels Found: " .. #filtered .. " | No results for page " .. page .. " (startIndex: " .. startIndex .. ")")
        return {}
    end
    
    -- Collect paged results
    local paged = {}
    for i = startIndex, endIndex do
        if filtered[i] then
            table.insert(paged, filtered[i])
        end
    end
    
    print("Total Novels Found: " .. #filtered .. " | Paged Results: " .. #paged .. " | Page: " .. page)
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