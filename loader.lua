-- Game scripts are hosted in the root of this public GitHub repository.
local REPOSITORY = "Casual0developer/Afright"
local BRANCH = "main"
local API_URL = "https://api.github.com/repos/" .. REPOSITORY .. "/contents?ref=" .. BRANCH
local RAW_URL = "https://raw.githubusercontent.com/" .. REPOSITORY .. "/" .. BRANCH .. "/"

local placeId = tostring(game.PlaceId)
local matchingName = placeId .. ".lua"

if type(loadstring) ~= "function" then
    warn("[Game Loader] This executor must support loadstring.")
    return
end

-- Enumerate repository root files so adding <PlaceId>.lua needs no loader edit.
local foundMatch = false
local listingAvailable = false
local listingOk, listingOrError = pcall(function()
    local HttpService = game:GetService("HttpService")
    return HttpService:JSONDecode(game:HttpGet(API_URL))
end)
if listingOk and type(listingOrError) == "table" and listingOrError.message == nil then
    listingAvailable = true
    for _, entry in ipairs(listingOrError) do
        if type(entry) == "table" and entry.type == "file" and entry.name == matchingName then
            foundMatch = true
            break
        end
    end
end

if listingAvailable and not foundMatch then
    print("[Game Loader] No script found for PlaceId " .. placeId .. " (expected " .. matchingName .. ").")
    return
end

-- The raw URL is an exact filename lookup and also works if GitHub's API
-- listing is unavailable or rate limited.
local fetchOk, sourceOrError = pcall(function()
    return game:HttpGet(RAW_URL .. matchingName)
end)
if not fetchOk or type(sourceOrError) ~= "string" or sourceOrError == "" then
    warn("[Game Loader] Could not download " .. matchingName .. ": " .. tostring(sourceOrError))
    return
end

local compileOk, script, compileError = pcall(loadstring, sourceOrError)
if not compileOk or type(script) ~= "function" then
    warn("[Game Loader] Could not compile " .. matchingName .. ": " .. tostring(compileError or script))
    return
end

local runOk, runError = pcall(script)
if not runOk then
    warn("[Game Loader] Error in " .. matchingName .. ": " .. tostring(runError))
end
