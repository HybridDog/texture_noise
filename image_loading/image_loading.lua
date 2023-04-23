-- Abstraction of opening image files
assert(path_texture_noise, "A global \"path_texture_noise\" " ..
	"variable has to be specified for the require and dofile functions.")
local pngImage = dofile(path_texture_noise .. "/image_loading/png-lua/png.lua")

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
