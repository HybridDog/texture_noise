-- Abstraction of opening image files

local path_png_lua = (...).path .. "/png-lua"
local pngImage = assert(
	loadfile(path_png_lua .. "/png.lua"){path = path_png_lua})

-- https://www.w3.org/TR/PNG-Chunks.html
local png_color_type = {[0] = "greyscale", nil, "RGB", "indexed",
	"greyscale with alpha", nil, "RGBA"}

-- Load a single-channel (greyscale, no alpha) image.
-- Values are in [0, 1] and no EOTF is applied on the raw pixel values, e.g.
-- no sRGB gamma correction (we don not want this for heightmaps).
-- Indices of the returned pixels array start from one.
-- Returns {width = int, height = int, pixels = {double, double, …,
--   double}}
local function load_image(path)
	local img = pngImage(path, nil, false, false)
	if not png_color_type[img.colorType] then
		error("Unknown PNG colorType: " .. img.colorType)
	elseif png_color_type[img.colorType] ~= "greyscale" then
		error("Only greyscale images are currently supported. " ..
			"The colour type is " .. png_color_type[img.colorType])
	end
	local pixels = {}
	local i = 1
	local normaliser = 1.0 / (2.0 ^ img.depth - 1)
	for y = 1, img.height do
		for x = 1, img.width do
			pixels[i] = img.pixels[y][x].R * normaliser
			i = i+1
		end
	end
	return {width = img.width, height = img.height, pixels = pixels}
end

return load_image
