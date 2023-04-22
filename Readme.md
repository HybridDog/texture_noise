Currently only greyscale PNG images are supported.
In noise images, the smallest and biggest grey value should ideally be 0 and 255
(in the 8-bit case).

# TODO

* Implement a (simplified) stochastic texture sampling in Lua with a convenient
  interface for noise generation somewhat similar to Minetest's perlin noise
* Options for interpolation of the gaussianized texture:
  nearest, linear, cubic (with parameters), perhaps mpv's spline36.
  Perhaps option for the interpolation of the LUT
  Texture and its sampling abstracted in a class
* Noise generation like perlin noise with octaves etc.,
  only the perlin noise's white noise replaced by the texture-based noise
* Random transformation matrices (rotation, shear, etc.) instead of only a
  random translation (patch offset) per triangle grid point
* Investigation of limitations due to quantisation; are 8-bit textures
  sufficient for heightmaps with this algorithm or not?
* Test if png-lua works correctly with 16-bit images, i.e. does not quantize
  away stuff
* Describe demo usage in this Readme
