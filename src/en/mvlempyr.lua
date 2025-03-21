-- {"id":620191,"ver":"1.0.1","libVer":"1.0.6","author":""}

local json = Require("dkjson")

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
	local url = expandURL(chapterURL)
	--- Chapter page, extract info from it.
	local document = GETDocument(url)
    local htmlElement = document:selectFirst("#chapter")
    return pageOfElem(htmlElement, true)
end

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
    local img = document:selectFirst("img.novel-image2"):attr("src") or imageURL
    local code = document:selectFirst("#novel-code"):text()
    local headers = HeadersBuilder():add("Origin", "https://www.mvlempyr.com"):build()
    local tags = json.GET("https://chp.mvlempyr.net/wp-json/wp/v2/tags?slug=" .. code, headers)
    local chapter_data = json.GET("https://chp.mvlempyr.net/wp-json/wp/v2/posts?tags=" .. tags[1].id .. "&per_page=500&page=1", headers)
    local chapters = {}
    for i, v in next, chapter_data do
        table.insert(chapters, NovelChapter {
            order = v.acf.chapter_number,
            title = v.acf.ch_name,
            link = shrinkURL(v.link)
        })
    end
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
        listing_page_parm = document:selectFirst("a.painationbutton.w--current,a.w-pagination-next")
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
    return map(document:select("div.searchlist[role=\"listitem\"]"), function(v)
        return Novel {
            title = v:selectFirst("h2"):text(),
            link = "https://www.mvlempyr.com/" ..v:selectFirst("a"):attr("href"),
            imageURL = v:selectFirst("img"):attr("src")
        }
    end)
end

local function search(data)
    local query = data[QUERY]
    local document = GETDocument("https://www.mvlempyr.com/advance-search")
    return mapNotNil(document:select("div.searchitem"), function(v)
        local name = v:selectFirst(".novelsearchname"):text()
        if not name:lower():match(query) then
            return nil
        end
        return NovelInfo {
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
    isSearchIncrementing = false,
    hasCloudFlare = true,
    search = search,
	imageURL = imageURL,
	chapterType = ChapterType.HTML,
    startIndex = startIndex,
}