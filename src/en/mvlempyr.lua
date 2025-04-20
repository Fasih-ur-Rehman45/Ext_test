-- {"id":620191,"ver":"1.0.3","libVer":"1.0.0","author":""}

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
    return url
end

local function expandURL(url, _)
	return url
end

local startIndex = 1

--- @param chapterURL string The chapters shrunken URL.
--- @return string Strings @of chapter
local function getPassage(chapterURL)
    -- Thanks to bigr4nd for figuring out that somehow .space domain bypasses cloudflare
	local url = expandURL(chapterURL):gsub("(%w+://[^/]+)%.net", "%1.space")
	--- Chapter page, extract info from it.
	local document = GETDocument(url)
    local htmlElement = document:selectFirst("#chapter")
    local title = document:selectFirst(".ct-headline.ChapterName .ct-span"):text()
    local ht = "<h1>" .. title .. "</h1>"
    return pageOfElem(htmlElement, true)
end

local function calculateTagId(novel_code)
    local t = bigint.new("1999999997")
    local c = bigint.modulus(bigint.new("7"), t);
    local d = tonumber(novel_code);
    local u = bigint.new(1);
    while d > 0 do
        -- print(bigint.unserialize(t, "string"), bigint.unserialize(c, "string"), d, bigint.unserialize(u, "string"))
        if (d % 2) == 1 then
            u = bigint.modulus((u * c), t)
        end
        c = bigint.modulus((c * c), t);
        d = math.floor(d/2);
    end
    return bigint.unserialize(u, "string")
end

--- Load info on a novel.
---
--- Required.
---
--- @param novelURL string shrunken novel url.
--- @return NovelInfo
local function parseNovel(novelURL)
	local url = expandURL(novelURL)
	--- Novel page, extract info from it.
	local document = GETDocument(url)
    local desc = ""
    map(document:select(".synopsis p"), function(p)
        desc = desc .. '\n' .. p:text()
    end)
    local img = document:selectFirst("img.novel-image2")
    img = img and img:attr("src") or imageURL
    local code = document:selectFirst("#novel-code"):text()
    local headers = HeadersBuilder():add("Origin", "https://www.mvlempyr.com"):build()
    local chapters = {}
    local page = 1
    repeat
        local chapter_data = json.GET("https://chap.mvlempyr.space/wp-json/wp/v2/posts?tags=" .. calculateTagId(code) .. "&per_page=500&page=" .. page, headers)
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

local search_page_parm
local function search(data)
    local query = data[QUERY]
    local document = GETDocument("https://www.mvlempyr.com/advance-search" .. (search_page_parm and (search_page_parm .. data[PAGE]) or ""))
    if not search_page_parm then
        search_page_parm = document:selectFirst("[role=\"navigation\"]:has(.paginationbuttonwrapper) [aria-label=\"Next Page\"]")
        if not search_page_parm then
            error(document)
        end
        search_page_parm = search_page_parm:attr("href")
        if not search_page_parm then
            error("Failed to find search href")
        end
        search_page_parm = search_page_parm:match("%?[^=]+=")
        if not search_page_parm then
            error("Failed to find search match")
        end
    end
    return mapNotNil(document:select(".novelcolumn"), function(v)
        local name = v:selectFirst(".novelcolumcontent h2"):text()
        if not name:lower():match(query) then
            return nil
        end
        return Novel {
            title = name,
            link = "https://www.mvlempyr.com/" ..v:selectFirst("a"):attr("href"),
            imageURL = imageURL
        }
    end)
end

-- Return all properties in a lua table.
return {
	-- Required
	id = id,
	name = name,
	baseURL = baseURL,
	listings = {
        Listing("Default", true, getListing)
    }, -- Must have at least one listing
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
