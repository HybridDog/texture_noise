
# Usage

To use this in a lua program inside a git repository, I recommend to add the files with git subtree, for example:
```sh
git subtree add --squash --prefix=texture_noise git@github.com:HybridDog/texture_noise.git
```
You may need to change the prefix to some subdirectory, or change the datastructures repository url if you want to use some fork of this repository.
After adding the subtree and assuming that the greyscale image `example_heightmap.png` exists, we can use the `TextureNoise` class in a Lua file:
```Lua
local path = […]
-- The `path_texture_noise` global variable has to be set so that
-- `texture_noise.lua` can load other files, e.g. the PNG decoder.
path_texture_noise = path .. "/texture_noise"
local TextureNoise = dofile(path_texture_noise .. "/texture_noise.lua")

-- Create an object for sampling the procedural noise
local tn = TextureNoise{
	path_image = path .. "/example_heightmap.png",
	grid_scaling = 3.0,
	interpolation = "linear"
}

function myfunc()
	-- […]
	-- Sample the procedural noise with a horizontal and vertical scaling of
	-- 1/0.3
	local values = tn:sampleArea({x1, y1}, {x2, y2}, {0.3, 0, 0, 0.3})
	-- […]
end
```

The `demo.lua` script can be used to test the noise with a given image and
other parameters and can be helpful to find a good `grid_scaling`.
It requires luavips and argparse from luarocks.
See `demo.lua --help` for usage information.


# API

## TextureNoise

### Initialisation

`TextureNoise(args)` creates a new TextureNoise object. `args` is a table with
the following fields:
* `path_image`: A path to the input image file.
  The image should be tileable and work well with the stochastic texture
  sampling algorithm.
  Currently only greyscale PNG images are supported.
  The smallest and biggest grey value should ideally be 0 and 255
  (in the 8-bit case).
  16-bit images are supported, which may be helpful against numerical precision
  problems.
* `grid_scaling`: A number for the scaling of the triangle grid.
  Higher values mean a coarser grid and lead to better pattern preservation
  at the cost of more visible tiling.
  If set too high, the result looks like a simple tiling of the input image,
  whereas if set too low, input image features are lost and the result is noisy.
  A good value can be found with trial and error, and `3.0` may be a good
  starting point.
* `interpolation`: Interpolation of the gaussianised texture when it is sampled.
  Possible values: `"nearest"`, `"linear"`.
  `"nearest"` is the fastest option and should therefore always be chosen if
  the noise is sampled without transformation.
* `lut_size`: Number of elements in the lookup table.
  Optional; defaults to `256`.
  For certain images, such as a few bright stars on a large black background,
  the histogram has a high peak and the transformation works badly;
  increasing `lut_size` may help in this case.

The initialisation happens lazily, i.e. the first time the noise is sampled,
`path_image` is loaded from disk and processed, so sampling the noise the first
time takes longer than the following times.


### Methods

* `sampleArea(pos1, pos2[, transformation])`: Sample the noise at multiple
  positions.
  `pos1` and `pos2` are two-element arrays, e.g. `{4, 51}`, and define a grid
  of sample positions.
  `transformation` is a 2x2 position transformation matrix encoded
  row-major in a flat array and defaults to the identity matrix.
  With this argument, it is possible to sample the noise with a
  scale, rotation, mirroring and shear; for example, `{0.5, 0, 0, 0.5}` makes
  the noise twice as large.
  The return value of this method is a flat array which begins at index `1` and
  has the noise samples in raster scan order; all values are within `[0, 1]`.
* `sample(pos)`: Sample the noise at the position `pos`.
  The return value is a number in `[0, 1]`.


# TODO

* Noise generation like perlin noise with octaves etc.,
  only the perlin noise's gradient noise replaced by the texture-based noise
* If available, use Minetest's pcgrandom, do not save grid point hashes forever, add a seed
* Add an interface which is similar to Minetest's perlin noise for ease of use
* More options for interpolation of the gaussianized texture:
  smoothstep, cubic (with parameters), perhaps mpv's spline36.
  Perhaps option for the interpolation of the LUT
  Texture and its sampling abstracted in a class
* Random transformation matrices (rotation, shear, etc.) instead of only a
  random translation (patch offset) per triangle grid point
* Investigation of limitations due to quantisation; are 8-bit textures
  sufficient for heightmaps with this algorithm or not?
* If available, use Minetest's deflate in PNG decoding for performance
* Test if png-lua works correctly with 16-bit images, i.e. does not quantize
  away stuff
* Code cleanup and practical application
