-- {"id":10255,"ver":"1.0.0","libVer":"1.0.0","author":""}


local baseURL = "https://wtr-lab.com/"

--- @param url string
--- @param type int 
local function shrinkURL(url)
    return url:gsub(baseURL, "")
end

--- @param url string
--- @param type int 
local function expandURL(url)
    return baseURL .. url
end

--- @type Filter[] | Array
local searchFilters = {
    DropdownFilter(1, "Order by", { "View", "Name", "Addition Date", "Reader", "Chapter" }),
    DropdownFilter(2, "Sort by", { "Descending", "Ascending" }),
    DropdownFilter(3, "Status", { "All", "Ongoing", "Completed" })
}

--- @type ChapterType
local chapterType = ChapterType.HTML
--- @type Listing[] | Array
local listings = {
    Listing("Popular Novels", true, function(data)
        --- @type int
        local page = data[PAGE]
        local url = baseURL .. "en/novel-list?orderBy=" .. data[1] .. "&order=" .. data[2] .. "&filter=" .. data[3] .. "&page=" .. page
        local document = GETDocument(url)
        local novels = {}
        for i, element in ipairs(document:select(".serie-item")) do
            local novel = {
                name = element:selectFirst(".title-wrap > a"):text(),
                cover = element:selectFirst("img"):attr("src"),
                path = element:selectFirst("a"):attr("href")
            }
            table.insert(novels, novel)
        end
        return novels
    end)
}
--- @param chapterURL string 
--- @return string Strings 
local function getPassage(chapterURL)
    local url = expandURL(chapterURL, KEY_CHAPTER_URL)
    local document = GETDocument(url)
    local chapterJson = document:selectFirst("#__NEXT_DATA__"):html()
    local jsonData = JSONDecode(chapterJson)
    local chapterContent = JSONDecode(jsonData.props.pageProps.serie.chapter_data.data.body)
    local htmlString = ""
    for i, text in ipairs(chapterContent) do
        htmlString = htmlString .. "<p>" .. text .. "</p>"
    end

    return htmlString
end

--- @param novelURL string
--- @return NovelInfo
local function parseNovel(novelURL)
    local url = expandURL(novelURL, KEY_NOVEL_URL)
    local document = GETDocument(url)
    return NovelInfo {
    title = document:selectFirst("h1.text-uppercase"):text(),
    imageURL = document:selectFirst(".img-wrap > img"):attr("src"),
    description = document:selectFirst(".lead"):text():trim(),
    genres = document:selectFirst("td:contains('Genre')"):next():select("a"):eachText():join(", "),
    author = document:selectFirst("td:contains('Author')"):next():text():gsub("[%t\n]", ""),
    
    status =({
    Ongoing = NovelStatus.PUBLISHING,
    Completed = NovelStatus.COMPLETED,})
    [document:selectFirst("td:contains('Status')"):next():text():gsub("[%t\n]", "")]
    }
end

--- @param data table @of applied filter values [QUERY] is the search query, may be empty.
--- @return Novel[] | Array

local function search(data)
    local url = baseURL .. "api/search"
    local response = POST(url, { text = data[QUERY] })
    local recentNovel = JSONDecode(response)
    local novels = {}
    for i, datum in ipairs(recentNovel.data) do
        local novel = {
            name = datum.data.title,
            cover = datum.data.image,
            path = "en/serie-" .. datum.raw_id .. "/" .. datum.slug
        }
        table.insert(novels, novel)
    end

    return novels
end

return {
    id = 10255,
    name = "WTR-LAB",
    baseURL = baseURL,
    imageURL = "https://wtr-lab.com/flask-white.svg",
    hasSearch = true,
    search = search,
    listings = listings,
    getPassage = getPassage,
    chapterType = chapterType.HTML,
    parseNovel = parseNovel,
    shrinkURL = shrinkURL,
    expandURL = expandURL,
}
