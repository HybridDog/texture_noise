-- Script for testing
-- Requires vips and argparse from luarocks
local vips = require"vips"
local argparse = require"argparse"
-- Path to this file; FIXME: find a better way to determine it
path_texture_noise = io.popen("pwd -P"):read("*a"):sub(1, -2)
print(path_texture_noise)
local load_image = dofile(path_texture_noise ..
	"/image_loading/image_loading.lua")

local function parse_args()
	local parser = argparse(){
		description = "Texture-based procedural noise testing script (WIP)"
	}
	parser:argument("input", "Input image")
	parser:argument("output", "Output image")
	--~ parser:argument{
		--~ name = "grid-scaling",
		--~ description = "Scaling of the triangle grid",
		--~ convert = tonumber
	--~ }
	return parser:parse()
end

-- Convert an array of numbers to a greyscale vips image without OETF
local function data_to_image(values, width)
	assert(type(values) == "table")
	assert(type(values[1]) == "number")
	local height = (#values + 1) / width
	assert(height == math.floor(height))
	local array = {}
	for y = 0, height-1 do
		local vi = y * width
		local data = {0.0}
		for x = 1, width do
			data[x] = values[vi]
			--~ data[x] = x / width
			vi = vi+1
		end
		array[y+1] = data
	end
	local img_grey = vips.Image.new_from_array(array)
	local img = vips.Image.bandjoin({img_grey, img_grey, img_grey})
	img = img:copy{interpretation = "srgb"} * 255.0 * 256.0
	return img
end

local function main()
	local args = parse_args()
	local img = load_image(args.input)

	-- Dummy, save with vips
	img = data_to_image(img.pixels, img.width)
	img:write_to_file(args.output .. "[bitdepth=16]")
end

main()
