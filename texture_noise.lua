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

-- Nearest-neighbour sampling on an image with repeating border behaviour
local function sample_img_nearest(img, pos)
	local x = math.floor(pos[1]) % img.width
	local y = math.floor(pos[2]) % img.height
	return img.pixels[y * img.width + x + 1]
end


local TextureNoise = {}
setmetatable(TextureNoise, {__call = function(_, path_image)
	local lut_size = 256
	local obj = {
		path_image = path_image,
		lut_size = lut_size,
		initialised = false
	}
	setmetatable(obj, TextureNoise)
	return obj
end})
TextureNoise.__index = {
	-- Used for lazy initialisation
	_init = function(self)
		self.img = load_image(self.path_image)
		self.lut = histogram_transform(self.img.pixels, self.lut_size)
		self.initialised = true
	end,

	sample = function(self, pos)
		if not self.initialised then
			self:_init()
		end
		return apply_lut(self.lut, sample_img_nearest(self.img, pos))
	end,

	sampleArea = function(self, pos1, pos2)
		if not self.initialised then
			self:_init()
		end
		local values = {}
		local vi = 1
		for y = pos1[2], pos2[2] do
			for x = pos1[1], pos2[1] do
				values[vi] = self:sample({x, y})
				vi = vi+1
			end
		end
		return values
	end,
}

return TextureNoise