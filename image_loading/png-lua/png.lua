-- The MIT License (MIT)

-- Copyright (c) 2013 DelusionalLogic

-- Permission is hereby granted, free of charge, to any person obtaining a copy of
-- this software and associated documentation files (the "Software"), to deal in
-- the Software without restriction, including without limitation the rights to
-- use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
-- the Software, and to permit persons to whom the Software is furnished to do so,
-- subject to the following conditions:

-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.

-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
-- FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
-- COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
-- IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
-- CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

local deflate = require("deflatelua")
local requiredDeflateVersion = "0.3.20111128"

if (deflate._VERSION ~= requiredDeflateVersion) then
    error("Incorrect deflate version: must be "..requiredDeflateVersion..", not "..deflate._VERSION)
end

local function bsRight(num, pow)
    return math.floor(num / 2^pow)
end

local function bsLeft(num, pow)
    return math.floor(num * 2^pow)
end

local function bytesToNum(bytes)
    local n = 0
    for k,v in ipairs(bytes) do
        n = bsLeft(n, 8) + v
    end
    if (n > 2147483647) then
        return (n - 4294967296)
    else
        return n
    end
    n = (n > 2147483647) and (n - 4294967296) or n
    return n
end

local function readInt(stream, bps)
    local bytes = {}
    bps = bps or 4
    for i=1,bps do
        bytes[i] = stream:read(1):byte()
    end
    return bytesToNum(bytes)
end

local function readChar(stream, num)
    num = num or 1
    return stream:read(num)
end

local function readByte(stream)
    return stream:read(1):byte()
end

local function getDataIHDR(stream, length)
    local data = {}
    data["width"] = readInt(stream)
    data["height"] = readInt(stream)
    data["bitDepth"] = readByte(stream)
    data["colorType"] = readByte(stream)
    data["compression"] = readByte(stream)
    data["filter"] = readByte(stream)
    data["interlace"] = readByte(stream)
    return data
end

local function getDataIDAT(stream, length, oldData)
    local data = {}
    if (oldData == nil) then
        data.data = readChar(stream, length)
    else
        data.data = oldData.data .. readChar(stream, length)
    end
    return data
end

local function getDataPLTE(stream, length)
    local data = {}
    data["numColors"] = math.floor(length/3)
    data["colors"] = {}
    for i = 1, data["numColors"] do
        -- palette colours are always 8-bit RGB
        data.colors[i] = {
            R = readByte(stream),
            G = readByte(stream),
            B = readByte(stream)
        }
    end
    return data
end

local function extractChunkData(stream)
    local chunkData = {}
    local length
    local type
    local crc

    while type ~= "IEND" do
        length = readInt(stream)
        type = readChar(stream, 4)
        if (type == "IHDR") then
            chunkData[type] = getDataIHDR(stream, length)
        elseif (type == "IDAT") then
            chunkData[type] = getDataIDAT(stream, length, chunkData[type])
        elseif (type == "PLTE") then
            chunkData[type] = getDataPLTE(stream, length)
        else
            readChar(stream, length)
        end
        crc = readChar(stream, 4)
    end

    return chunkData
end

local function bitFromColorType(colorType)
    if colorType == 0 then return 1 end
    if colorType == 2 then return 3 end
    if colorType == 3 then return 1 end
    if colorType == 4 then return 2 end
    if colorType == 6 then return 4 end
    error 'Invalid colortype'
end

local function paethPredict(a, b, c)
    local p = a + b - c
    local varA = math.abs(p - a)
    local varB = math.abs(p - b)
    local varC = math.abs(p - c)

    if varA <= varB and varA <= varC then
        return a
    elseif varB <= varC then
        return b
    else
        return c
    end
end

-- Apply PNG filter algorithms as explained at
-- https://www.w3.org/TR/PNG-Filters.html
local function applyFilter(filter_type, bpp, scanline_prev, scanline)
    if filter_type == 0 then  -- None
        return
    elseif filter_type == 1 then  -- Sub
        for x = 1, #scanline do
            local byte_left = scanline[x - bpp] or 0
            scanline[x] = (scanline[x] + byte_left) % 256
        end
    elseif filter_type == 2 then  -- Up
        for x = 1, #scanline do
            local byte_above = scanline_prev[x] or 0
            scanline[x] = (scanline[x] + byte_above) % 256
        end
    elseif filter_type == 3 then  -- Average
        for x = 1, #scanline do
            local byte_left = scanline[x - bpp] or 0
            local byte_above = scanline_prev[x] or 0
            scanline[x] = (scanline[x]
                + math.floor((byte_above + byte_left) / 2)) % 256
        end
    elseif filter_type == 4 then  -- Paeth
        for x = 1, #scanline do
            local byte_left = scanline[x - bpp] or 0
            local byte_above = scanline_prev[x] or 0
            local byte_above_left = scanline_prev[x - bpp] or 0
            scanline[x] = (scanline[x]
                + paethPredict(byte_left, byte_above, byte_above_left)) % 256
        end
    else
        error("Unknown filter type: " .. filter_type)
    end
end

-- Convert raw scanline bits to pixels
local function getPixelRow(scanline, depth, colour_type, palette)
    -- Handle different bit depths
    local flat_values = {}
    if depth == 8 then
        flat_values = scanline
    elseif depth == 16 then
        for x = 1, #scanline / 2 do
            flat_values[x] = scanline[2 * x - 1] * 256 + scanline[2 * x]
        end
    else
        -- depth < 8
        local values_per_byte = 8 / depth
        for i = 1, #scanline do
            local packed = scanline[i]
            for off = 1, values_per_byte do
                local x = (i - 1) * values_per_byte + off
                local rightshift = (off - 1) * depth
                flat_values[x] = math.floor(packed / 2 ^ rightshift)
                    % (2 ^ depth)
            end
        end
    end

    -- Handle colour types
    local num_channels = bitFromColorType(colour_type)
    local width = #flat_values / num_channels
    local vmax = 2 ^ depth - 1
    local pixel_row = {}
    if colour_type == 0 then  -- greyscale
        for x = 1, width do
            local grey = flat_values[x]
            pixel_row[x] = {R = grey, G = grey, B = grey, A = vmax}
        end
    elseif colour_type == 2 then  -- RGB
        for x = 1, width do
            local i = (x - 1) * 3 + 1
            pixel_row[x] = {R = flat_values[i], G = flat_values[i + 1],
                B = flat_values[i + 2], A = vmax}
        end
    elseif colour_type == 3 then  -- indexed
        for x = 1, width do
            local color = palette.colors[flat_values[x] + 1]
            pixel_row[x] = {R = color.R, G = color.G, B = color.B, A = vmax}
        end
    elseif colour_type == 4 then  -- greyscale with alpha
        for x = 1, width do
            local i = (x - 1) * 2 + 1
            local grey = flat_values[i]
            local alpha = flat_values[i + 1]
            pixel_row[x] = {R = grey, G = grey, B = grey, A = alpha}
        end
    else  -- colour_type == 6, RGBA
        for x = 1, width do
            local i = (x - 1) * 4 + 1
            pixel_row[x] = {R = flat_values[i], G = flat_values[i + 1],
                B = flat_values[i + 2], A = flat_values[i + 3]}
        end
    end

    return pixel_row
end

local function getPixels(stream, width, height, depth, colour_type, palette,
        prog_callback, pixels)
    local scanline_bpp = math.ceil(depth / 8 * bitFromColorType(colour_type))
    local scanline_len = math.ceil(depth / 8 * bitFromColorType(colour_type)
        * width)
    local scanline_prev = {}
    for y = 1, height do
        local filter_type = readByte(stream)
        local scanline = stream:readBytes(scanline_len)
        applyFilter(filter_type, scanline_bpp, scanline_prev, scanline)
        scanline_prev = scanline
        local pixel_row = getPixelRow(scanline, depth, colour_type, palette)
        if prog_callback then
            prog_callback(y, height, pixel_row)
        end
        if pixels then
            pixels[y] = pixel_row
        end
    end
end


local function pngImage(path, progCallback, verbose, memSave)
    local stream = io.open(path, "rb")
    local chunkData
    local imStr
    local width = 0
    local height = 0
    local depth = 0
    local colorType = 0
    local output = {}
    local StringStream
    local function printV(msg)
        if (verbose) then
            print(msg)
        end
    end

    if readChar(stream, 8) ~= "\137\080\078\071\013\010\026\010" then
        error "Not a png"
    end

    printV("Parsing Chunks...")
    chunkData = extractChunkData(stream)
    if chunkData.IHDR.interlace ~= 0 then
        error("Interlacing is unsupported.")
    end

    width = chunkData.IHDR.width
    height = chunkData.IHDR.height
    depth = chunkData.IHDR.bitDepth
    colorType = chunkData.IHDR.colorType

    printV("Deflating...")
    deflate.inflate_zlib {
        input = chunkData.IDAT.data,
        output = function(byte)
            output[#output+1] = string.char(byte)
        end,
        disable_crc = true
    }
    StringStream = {
        str = table.concat(output),
        read = function(self, num)
            local toreturn = self.str:sub(1, num)
            self.str = self.str:sub(num + 1, self.str:len())
            return toreturn
        end,
        readBytes = function(self, num)
            -- FIXME: str.byte has a big number of return values which are
            -- unpacked into a table. How does this affect performance?
            return {self:read(num):byte(1, num)}
        end
    }

    printV("Creating pixelmap...")
    local pixels
    if not memSave then
        pixels = {}
    end
    getPixels(StringStream, width, height, depth, colorType, chunkData.PLTE,
        progCallback, pixels)

    printV("Done.")
    return {
        width = width,
        height = height,
        depth = depth,
        colorType = colorType,
        pixels = pixels or {}
    }
end

return pngImage
