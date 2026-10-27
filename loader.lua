-- Scan the executor folder containing this loader for <PlaceId>.lua.
local SCRIPT_DIRECTORY = "."
local placeId = tostring(game.PlaceId)
local matchingName = placeId .. ".lua"

if type(listfiles) ~= "function" or type(readfile) ~= "function" or type(loadstring) ~= "function" then
    warn("[Game Loader] This executor must support listfiles, readfile, and loadstring.")
    return
end

local listOk, files = pcall(listfiles, SCRIPT_DIRECTORY)
if not listOk or type(files) ~= "table" then
    warn("[Game Loader] Could not scan " .. SCRIPT_DIRECTORY .. ": " .. tostring(files))
    return
end

local matchingPath
for _, path in ipairs(files) do
    if type(path) == "string" then
        local name = path:match("[^/\\]+$") or path
        if name == matchingName then
            matchingPath = path
            break
        end
    end
end

if not matchingPath then
    print("[Game Loader] No script found for PlaceId " .. placeId .. " (expected " .. matchingName .. ").")
    return
end

local readOk, source = pcall(readfile, matchingPath)
if (not readOk or type(source) ~= "string") and matchingPath ~= matchingName then
    -- Some executors list full paths but read files by name in the same folder.
    readOk, source = pcall(readfile, matchingName)
end
if not readOk or type(source) ~= "string" then
    warn("[Game Loader] Could not read " .. matchingName .. ": " .. tostring(source))
    return
end

local compileOk, script, compileError = pcall(loadstring, source)
if not compileOk or type(script) ~= "function" then
    warn("[Game Loader] Could not compile " .. matchingName .. ": " .. tostring(compileError or script))
    return
end

local runOk, runError = pcall(script)
if not runOk then
    warn("[Game Loader] Error in " .. matchingName .. ": " .. tostring(runError))
end
