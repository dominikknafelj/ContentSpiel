# Contrast as WCAG 2.x measures it, for the two tests that hold the tokens'
# pairs: CS Studio's (`test/lib/admin_contrast_test.rb`) and the default
# theme's (`test/integration/design_tokens_test.rb`). Taken out of the
# second so both measure alike (contrast and buttons spec, "Testing").
module ContrastMeasure
  TOKEN = /--(?:th|cs)-[\w-]+/

  # A token's colour as linear-light sRGB, following `var()` to its value.
  # Hex and `oklch()` are the two notations the opaque tokens use; a colour
  # thinned out with `color-mix(… <share>%, transparent)` or written as
  # `rgba()` is painted over `under`, which a caller that expects one hands in.
  # A colour mixed of two tokens with `color-mix(in srgb, var(a) N%, var(b))`
  # (the Note block's tokens) is the two mixed, each read where the mix is;
  # `in oklab` (the Gallery's) mixes them in oklab.
  #
  # `inside` is what a band declares for everything in it. A name it
  # declares is the band's value, whose own `var()`s are read inside the
  # band too; any other name is the page's, computed on the page with the
  # page's values, as a custom property is inherited: computed.
  def resolve_colour(tokens, name, under: nil, inside: {})
    return resolve_colour(tokens, name, under: under) if inside.any? && !inside.key?(name)

    value = inside.fetch(name) { tokens.fetch(name) }.to_s.strip
    case value
    when /\Avar\((#{TOKEN})\)\z/o then resolve_colour(tokens, $1, under: under, inside: inside)
    when /\A#(\h{6})\z/ then $1.scan(/../).map { |pair| decode(pair.hex / 255.0) }
    when /\Aoklch\(([\d.]+) ([\d.]+) ([\d.]+)\)\z/ then oklch_to_linear_srgb($1.to_f, $2.to_f, $3.to_f)
    when /\Acolor-mix\(in srgb, var\((#{TOKEN})\) ([\d.]+)%, transparent\)\z/o
      under or flunk("#{name} is a thinned colour and nothing was named for it to be painted over")
      mix(resolve_colour(tokens, $1, inside: inside), under, $2.to_f / 100)
    when /\Acolor-mix\(in srgb, var\((#{TOKEN})\) ([\d.]+)%, var\((#{TOKEN})\)\)\z/o
      top, share, bottom = $1, $2.to_f / 100, $3
      mix(resolve_colour(tokens, top, under: under, inside: inside), resolve_colour(tokens, bottom, under: under, inside: inside), share)
    # In oklab a colour thinned with `transparent` keeps its own channels
    # (the mix is premultiplied, and transparent's are nothing), so it is
    # painted over `under` as the srgb one is; two colours are mixed in
    # oklab itself.
    when /\Acolor-mix\(in oklab, var\((#{TOKEN})\) ([\d.]+)%, transparent\)\z/o
      under or flunk("#{name} is a thinned colour and nothing was named for it to be painted over")
      mix(resolve_colour(tokens, $1, inside: inside), under, $2.to_f / 100)
    when /\Acolor-mix\(in oklab, var\((#{TOKEN})\) ([\d.]+)%, var\((#{TOKEN})\)\)\z/o
      top, share, bottom = $1, $2.to_f / 100, $3
      mix_oklab(resolve_colour(tokens, top, under: under, inside: inside), resolve_colour(tokens, bottom, under: under, inside: inside), share)
    when /\Argba\((\d+),\s*(\d+),\s*(\d+),\s*([\d.]+)\)\z/
      under or flunk("#{name} is a translucent colour and nothing was named for it to be painted over")
      mix([ $1, $2, $3 ].map { |channel| decode(channel.to_i / 255.0) }, under, $4.to_f)
    else flunk("#{name} is neither a hex colour, oklch(), rgba() nor a colour mixed with color-mix() in srgb or oklab: #{value}")
    end
  end

  # `color-mix(in srgb, top <share>, transparent)` (or `rgba()`) painted over
  # `under`: mixed in the encoded values, as a browser does, from and to
  # linear light.
  def mix(top, under, share)
    top.zip(under).map { |one, other| decode(encode(one) * share + encode(other) * (1 - share)) }
  end

  # `color-mix(in oklab, top <share>, under)` of two opaque colours: both
  # taken to oklab, mixed there, and brought back to linear light.
  def mix_oklab(top, under, share)
    one, other = [ top, under ].map { |rgb| linear_srgb_to_oklab(rgb) }
    oklab_to_linear_srgb(*one.zip(other).map { |a, b| a * share + b * (1 - share) })
  end

  def contrast(one, other)
    light, dark = [ one, other ].map { |rgb| rgb.zip([ 0.2126, 0.7152, 0.0722 ]).sum { |value, weight| value * weight } }.minmax.reverse
    (light + 0.05) / (dark + 0.05)
  end

  # Björn Ottosson's OKLab to linear sRGB matrices; out-of-gamut channels
  # are clipped, as a browser does when it paints the colour on an sRGB
  # screen.
  def oklch_to_linear_srgb(lightness, chroma, hue)
    oklab_to_linear_srgb(lightness, chroma * Math.cos(hue * Math::PI / 180), chroma * Math.sin(hue * Math::PI / 180))
  end

  def oklab_to_linear_srgb(lightness, a, b)
    l = (lightness + 0.3963377774 * a + 0.2158037573 * b)**3
    m = (lightness - 0.1055613458 * a - 0.0638541728 * b)**3
    s = (lightness - 0.0894841775 * a - 1.2914855480 * b)**3
    [ 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
      -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
      -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s ].map { |channel| channel.clamp(0.0, 1.0) }
  end

  def linear_srgb_to_oklab(rgb)
    red, green, blue = rgb
    l = Math.cbrt(0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue)
    m = Math.cbrt(0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue)
    s = Math.cbrt(0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue)
    [ 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
      1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
      0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s ]
  end

  private

  def decode(value) = value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4

  def encode(value) = value <= 0.0031308 ? value * 12.92 : 1.055 * value**(1 / 2.4) - 0.055
end
