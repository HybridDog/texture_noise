-- Script for testing
-- Requires vips and argparse from luarocks
local vips = require"vips"
local argparse = require"argparse"
-- Path to this file; FIXME: find a better way to determine it
local path_texture_noise = io.popen("pwd -P"):read("*a"):sub(1, -2)
local texture_noise = assert(loadfile(
	path_texture_noise .. "/texture_noise.lua"){path = path_texture_noise})

local function parse_args()
	local parser = argparse(){
		description = "Texture-based procedural noise testing script (WIP)"
	}
	parser:argument("input", "Input image")
	parser:argument("output", "Output image")
	parser:argument{
		name = "grid-scaling",
		description = "Scaling of the triangle grid",
		convert = tonumber
	}
	parser:argument{
		name = "interpolation",
		description = "Interpolation of the gaussianised texture",
		choices = {"nearest", "linear", "smoothstep", "quintic"}
	}
	parser:option{
		name = "--transform",
		description = "Only without --stack. " ..
			"Row-major 2x2 transformation matrix elements for the " ..
			"sample position transformation",
		args = 4,
		convert = {tonumber, tonumber, tonumber, tonumber},
		default = {1, 0, 0, 1}
	}
	parser:option{
		name = "--width",
		description = "Output image width",
		default = 500,
		convert = tonumber
	}
	parser:option{
		name = "--height",
		description = "Output image height",
		default = 500,
		convert = tonumber
	}
	parser:flag{
		name = "--stack",
		description = "Use a stacked noise",
	}
	parser:option{
		name = "--octaves",
		description = "Only with --stack. Number of entries in the noise stack",
		default = 3,
		convert = tonumber
	}
	parser:option{
		name = "--spread",
		description = "Only with --stack. 'wavelength' of the "
			.. "lowest-frequency stack entry",
		default = 16,
		convert = tonumber
	}
	parser:option{
		name = "--persistence",
		description = "Only with --stack. Amplitude reduction factor per " ..
			"stack entry",
		default = 0.5,
		convert = tonumber
	}
	parser:option{
		name = "--lacunarity",
		description = "Only with --stack. Inverse of the 'wavelength' " ..
			"reduction factor per stack entry",
		default = 2.0,
		convert = tonumber
	}
	return parser:parse()
end

-- Convert an array of numbers to a greyscale vips image without OETF
local function data_to_image(values, width)
	assert(type(values) == "table")
	assert(type(values[1]) == "number")
	local height = (#values) / width
	assert(height == math.floor(height))
	local array = {}
	for y = 0, height-1 do
		local vi = y * width
		local data = {0.0}
		for x = 1, width do
			data[x] = values[vi + 1]
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
	local texture_noise_params = {
		path_image = args.input,
		grid_scaling = args["grid-scaling"],
		interpolation = args.interpolation,
		seed = 0
	}
	local values
	if args.stack then
		local tn = texture_noise.NoiseStacked{
			texture_noise_params = texture_noise_params,
			octaves = args.octaves,
			spread = args.spread,
			persistence = args.persistence,
			lacunarity = args.lacunarity,
		}
		values = tn:sampleArea({0, 0}, {args.width - 1, args.height - 1})
	else
		local tn = texture_noise.Noise(texture_noise_params)
		values = tn:sampleArea({0, 0}, {args.width - 1, args.height - 1},
			args.transform)
	end

	-- Dummy, save with vips
	local img = data_to_image(values, args.width)
	img:write_to_file(args.output .. "[bitdepth=16]")
end

main()
