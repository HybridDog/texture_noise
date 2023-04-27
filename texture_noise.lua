local load_image = dofile(path_texture_noise ..
	"/image_loading/image_loading.lua")

local cdf, inv_cdf
do
	-- Functions for the Gaussian probability distribution,
	-- based on code from the original stochastic texture sampling demo

	local gaussian_mean = 0.5
	local gaussian_std = 0.16666

	local function erf(x)
		local sign = x < 0 and -1 or 1
		x = math.abs(x)
		local t = 1.0 / (1.0 + 0.3275911 * x)
		local y = 1.0 - (((((1.061405429 * t + -1.453152027) * t) + 1.421413741)
			* t + -0.284496736) * t + 0.254829592) * t * math.exp(-x * x)
		return sign * y
	end

	local function inv_erf(x)
		local w = -math.log((1.0 - x) * (1.0 + x))
		local p
		if w < 5 then
			w = w - 2.500000
			p = 2.81022636e-08
			p = 3.43273939e-07 + p * w
			p = -3.5233877e-06 + p * w
			p = -4.39150654e-06 + p * w
			p = 0.00021858087 + p * w
			p = -0.00125372503 + p * w
			p = -0.00417768164 + p * w
			p = 0.246640727 + p * w
			p = 1.50140941 + p * w
		else
			w = math.sqrt(w) - 3.000000
			p = -0.000200214257
			p = 0.000100950558 + p * w
			p = 0.00134934322 + p * w
			p = -0.00367342844 + p * w
			p = 0.00573950773 + p * w
			p = -0.0076224613 + p * w
			p = 0.00943887047 + p * w
			p = 1.00167406 + p * w
			p = 2.83297682 + p * w;
		end
		return p * x;
	end

	-- Gaussian cumulative distribution function
	function cdf(x)
		return 0.5 * (1 + erf((x - gaussian_mean) /
			(gaussian_std * math.sqrt(2.0))))
	end

	-- Inverse of the Gaussian cumulative distribution function
	function inv_cdf(x)
		return gaussian_std * math.sqrt(2.0) * inv_erf(2.0 * x - 1.0)
			+ gaussian_mean
	end
end

-- Do a histogram transformation on values in-place and return a lookup table
-- for the inverse
local function histogram_transform(values, lut_size)
	local num_values = #values

	-- Create a sort permutation to index values in ascending order
	local perm = {}
	for i = 1, num_values do
		perm[i] = i
	end
	table.sort(perm, function(i1, i2)
		return values[i1] < values[i2]
	end)

	-- Create the LUT for the inverse histogram transformation
	local lut = {}
	for k = 1, lut_size do
		local u = cdf((k - 0.5) / lut_size)
		local i_perm = math.floor(u * num_values) + 1
		lut[k] = values[perm[i_perm]]
	end

	-- Do the histogram transformation
	for k = 1, num_values do
		local u = (k - 0.5) / num_values
		values[perm[k]] = inv_cdf(u)
	end

	return lut
end

local function apply_lut(lut, v)
	-- TODO: interpolation option for the LUT
	local lut_size = #lut
	local i = math.floor(v * lut_size) + 1
	i = math.max(1, math.min(i, lut_size))
	return lut[i]
end

-- Based on code from the deliot2019_openGLdemo
-- (https://eheitzresearch.wordpress.com/738-2/)
-- Compute local triangle barycentric coordinates and vertex IDs
local function triangle_grid(uv, grid_scaling)
	uv = {uv[1] * grid_scaling, uv[2] * grid_scaling}

	-- Skew input space into simplex triangle grid
	local skewed_coord = {uv[1], -0.57735027 * uv[1] + 1.15470054 * uv[2]}

	-- Compute local triangle vertex IDs and local barycentric coordinates
	local base_id = {math.floor(skewed_coord[1]), math.floor(skewed_coord[2])}
	local temp = {skewed_coord[1] - base_id[1], skewed_coord[2] - base_id[2], 0}
	temp[3] = 1.0 - temp[1] - temp[2]
	if temp[3] > 0.0 then
		return {temp[3], temp[2], temp[1]},
			{
				base_id,
				{base_id[1], base_id[2] + 1},
				{base_id[1] + 1, base_id[2]}
			}
	end
	return {-temp[3], 1.0 - temp[2], 1.0 - temp[1]},
		{
			{base_id[1] + 1, base_id[2] + 1},
			{base_id[1] + 1, base_id[2]},
			{base_id[1], base_id[2] + 1}
		}
end

-- Get a random offset vector at a triangle grid point
-- TODO: do not save them in a table and never forget them; and allow seeds
-- TODO: use pcgrandom
local offsets = {}
local function hash_vertex(pos)
	local vi = (pos[2] + 32768) * 65536 + pos[1] + 32768
	if not offsets[vi] then
		offsets[vi] = {math.random(), math.random()}
	end
	return offsets[vi]
end

-- The sampling functions here all use the repeat border behaviour,
-- i.e. out-of-bounds pixel positions are mapped to the opposite side of the
-- image so that it tiles.
-- The sampling of the 1D lookup table is different.
local sampling_functions = {
	-- Nearest-neighbour sampling of an image
	nearest = function(img, uv)
		local x = math.floor(uv[1] * img.width) % img.width
		local y = math.floor(uv[2] * img.height) % img.height
		return img.pixels[y * img.width + x + 1]
	end,

	-- Sampling with linear interpolation
	linear = function(img, uv)
		local w, h = img.width, img.height
		local x = uv[1] * w
		local y = uv[2] * h
		local x_floor = math.floor(x)
		local y_floor = math.floor(y)
		local cx = x - x_floor
		local cy = y - y_floor
		local x0 = x_floor % w
		local y0 = y_floor % h
		local x1 = (x0 + 1) % w
		local y1 = (y0 + 1) % h
		return (1.0 - cx) * (1.0 - cy) * img.pixels[y0 * w + x0 + 1]
			+ cx * (1.0 - cy) * img.pixels[y0 * w + x1 + 1]
			+ (1.0 - cx) * cy * img.pixels[y1 * w + x0 + 1]
			+ cx * cy * img.pixels[y1 * w + x1 + 1]
	end
}

local TextureNoise = {}
setmetatable(TextureNoise, {__call = function(_, args)
	local obj = {
		path_image = args.path_image,
		grid_scaling = args.grid_scaling,
		lut_size = args.lut_size or 256,
		initialised = false
	}
	obj.sample_img = sampling_functions[args.interpolation]
	if not obj.sample_img then
		error(("Unsupported interpolation mode: %s"):format(args.interpolation))
	end
	setmetatable(obj, TextureNoise)
	return obj
end})
TextureNoise.__index = {
	-- Used for lazy initialisation
	init = function(self)
		self.img = load_image(self.path_image)
		self.lut = histogram_transform(self.img.pixels, self.lut_size)
		self.initialised = true
	end,

	sample = function(self, pos)
		if not self.initialised then
			self:init()
		end
		local uv = {pos[1] / self.img.width, pos[2] / self.img.height}
		local weights, vertices = triangle_grid(uv, self.grid_scaling)
		local samples = {}
		for i = 1, 3 do
			-- Translate the texture at each triangle point and get the gaussian
			-- input
			local off = hash_vertex(vertices[i])
			samples[i] = self.sample_img(self.img,
				{uv[1] + off[1], uv[2] + off[2]})
		end
		-- Variance-preserving blending
		local g = weights[1] * samples[1] + weights[2] * samples[2]
			+ weights[3] * samples[3]
		g = (g - 0.5) * 1.0 / math.sqrt(weights[1] * weights[1]
			+ weights[2] * weights[2] + weights[3] * weights[3]) + 0.5
		-- Inverse histogram transformation
		return apply_lut(self.lut, g)
	end,

	sampleArea = function(self, pos1, pos2, transformation)
		-- Set the transformation to identity if it is omitted
		transformation = transformation or {1, 0, 0, 1}
		if not self.initialised then
			self:init()
		end
		local values = {}
		local vi = 1
		for y = pos1[2], pos2[2] do
			for x = pos1[1], pos2[1] do
				-- transformation is row-major
				local xt = transformation[1] * x + transformation[2] * y
				local yt = transformation[3] * x + transformation[4] * y
				values[vi] = self:sample({xt, yt})
				vi = vi+1
			end
		end
		return values
	end,
}

return TextureNoise
