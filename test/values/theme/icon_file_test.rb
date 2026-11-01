require "test_helper"
require "tmpdir"

# A theme's icon file: the fence it passes before the public site inlines
# it. The fence refuses; it rewrites nothing. What it reads must be read
# alike by the XML parser that checks it and by the HTML parser of the page
# the file is inlined into, so a name is compared whatever its case, its
# prefix or its namespace.
class Theme::IconFileTest < ActiveSupport::TestCase
  OUTLINE = <<~SVG.freeze
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <path d="M5 12h14"/><path d="m12 5 7 7-7 7"/>
    </svg>
  SVG

  # A theme's own icon of several classed layers, its own size and a ground
  # the theme's layout defines (the gradient `glow` is not in the file).
  LAYERED = <<~SVG.freeze
    <svg xmlns="http://www.w3.org/2000/svg" class="icon" viewBox="0 0 24 24" width="48" height="48"><path class="icon__halo" d="M3 12h13"/><path class="icon__line" d="M3 12h13"/><circle class="icon__glow" fill="url(#glow)" cx="21" cy="12" r="7"/><circle class="icon__dot" cx="21" cy="12" r="2"/></svg>
  SVG

  def problems(source, name: "assets/images/icons/a.svg")
    Dir.mktmpdir("icon") do |dir|
      path = Pathname(dir).join("a.svg")
      path.binwrite(source)
      Theme::IconFile.problems(path, file: name)
    end
  end

  def one_problem(source, *parts)
    found = problems(source)

    assert_equal 1, found.size, "#{source}\n#{found.inspect}"
    assert found.first.start_with?("assets/images/icons/a.svg"), found.first
    assert found.first.end_with?("."), found.first
    parts.each { |part| assert_includes found.first, part }
    found.first
  end

  def svg(inner, root: "") = %(<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 24 24"#{root}>#{inner}</svg>)

  test "a well-formed svg passes, and inline adds aria-hidden and focusable to its root and changes nothing else" do
    assert_empty problems(OUTLINE)

    inlined = Theme::IconFile.inline(OUTLINE)

    assert_equal OUTLINE.sub("<svg ", %(<svg aria-hidden="true" focusable="false" )).strip, inlined
    with_prolog = %(<?xml version="1.0" encoding="UTF-8"?>\n<!-- drawn by hand -->\n#{OUTLINE})

    assert_empty problems(with_prolog)
    assert_equal inlined, Theme::IconFile.inline(with_prolog), "the prolog is not the drawing: it is left out of the page"
  end

  test "a theme's own icon of classed layers, its own size and a layout's gradient passes and is inlined as written" do
    assert_empty problems(LAYERED)

    inlined = Theme::IconFile.inline(LAYERED)

    assert_equal LAYERED.strip.sub("<svg ", %(<svg aria-hidden="true" focusable="false" )), inlined
    assert_includes inlined, %(width="48" height="48")
    assert_includes inlined, %(fill="url(#glow)")
    assert_equal 4, Nokogiri::HTML5.fragment(inlined).css("svg > [class]").size

    already = LAYERED.sub("<svg ", %(<svg aria-hidden="true" ))

    assert_equal already.strip.sub("<svg ", %(<svg focusable="false" )), Theme::IconFile.inline(already),
                 "an attribute the root already has is not written twice"
  end

  test "a file that is not XML, has another root, is over 32 KB or holds a DOCTYPE or an entity is refused, each naming the file and what to take out" do
    one_problem("<svg><path></svg>", "not well-formed XML")
    one_problem("not svg at all", "not well-formed XML")
    one_problem(%(<html xmlns="http://www.w3.org/1999/xhtml"><svg/></html>), "root", "<svg>")
    one_problem(%(<svg viewBox="0 0 24 24"/>), "root", "http://www.w3.org/2000/svg")
    one_problem(%(<s:svg xmlns:s="http://www.w3.org/2000/svg"/>), "root", "prefix")
    one_problem(OUTLINE + "<!-- #{"x" * Theme::IconFile::MAX_BYTES} -->", "32 KB")
    one_problem(%(<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">\n#{OUTLINE}), "DOCTYPE")
    one_problem(%(<!DOCTYPE svg [<!ENTITY a "x">]>\n#{svg("<text>&a;</text>")}), "DOCTYPE")
    one_problem(svg("<text>&nbsp;</text>"), "entity")
    one_problem("#{OUTLINE}\xE9".b, "UTF-8")
    one_problem(%(<?xml version="1.0" encoding="ISO-8859-1"?>\n#{OUTLINE}), "UTF-8")

    assert_empty problems(svg("<text>&amp; &lt; &#x41;</text>")), "XML's own five and a character reference are no entity"
    assert_empty problems(OUTLINE.b + "<!-- #{"x" * (Theme::IconFile::MAX_BYTES - OUTLINE.bytesize - 9)} -->".b)
  end

  test "a script, a foreignObject, a style element, an on-attribute and an href that is not a fragment are each refused" do
    one_problem(svg("<script>alert(1)</script>"), "<script>")
    one_problem(svg("<foreignObject><div/></foreignObject>"), "<foreignObject>")
    one_problem(svg("<style>path{fill:red}</style>"), "<style>")
    one_problem(svg("", root: %( onload="alert(1)")), "onload")
    one_problem(svg(%(<use href="https://example.com/a.svg#b"/>)), "href")
    one_problem(svg(%(<use xlink:href="javascript:alert(1)"/>)), "href")

    assert_empty problems(svg(%(<use href="#g"/><use xlink:href="#g"/>)))
  end

  test "an id is refused anywhere, and a url() only names a fragment, never an address or data" do
    one_problem(svg(%(<path id="a" d="M0 0"/>)), "id")
    one_problem(svg("", root: %( id="icon")), "id")
    one_problem(svg(%(<circle fill="url(https://example.com/a.svg#g)" r="2"/>)), "url(")
    one_problem(svg(%(<circle filter="url(data:image/svg+xml,x)" r="2"/>)), "url(")
    one_problem(svg(%(<circle fill="u\\72l(//example.com/g)" r="2"/>)), "backslash")
    one_problem(svg(%(<circle style="fill:red" r="2"/>)), "style")

    assert_empty problems(svg(%(<circle fill="url(#glow)" stroke="url( '#line' )" filter="url(&quot;#soft&quot;)" r="2"/>)))
  end

  test "the fence is not fooled by a prefix, a case or a namespace: a prefixed script, ONLOAD, a use with a data address, an xlink bound to another prefix" do
    one_problem(svg(%(<s:script xmlns:s="http://www.w3.org/2000/svg">alert(1)</s:script>)), "script")
    one_problem(svg("<SCRIPT>alert(1)</SCRIPT>"), "script")
    one_problem(svg("<h:script xmlns:h=\"http://www.w3.org/1999/xhtml\">alert(1)</h:script>"), "script")
    one_problem(svg("<foreignobject/>"), "foreignObject")
    one_problem(svg("", root: %( ONLOAD="alert(1)")), "ONLOAD")
    one_problem(svg("", root: %( x:onload="alert(1)" xmlns:x="urn:x")), "onload")
    one_problem(svg(%(<use href="data:image/svg+xml;base64,PHN2Zz4="/>)), "href")
    one_problem(svg(%(<use HREF="javascript:alert(1)"/>)), "HREF")
    one_problem(svg(%(<use l:href="javascript:alert(1)" xmlns:l="http://www.w3.org/1999/xlink"/>)), "href")
    one_problem(%(<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="urn:not-xlink"><use xlink:href="javascript:alert(1)"/></svg>), "href")
  end

  # libxml says a prefix nobody declared and goes on, naming the attribute
  # `xlink:href` in no namespace; the page's HTML parser reads it as XLink's
  # href all the same.
  test "a prefix the file never declares is refused: an undeclared xlink:href and an undeclared x:onload" do
    one_problem(%(<svg xmlns="http://www.w3.org/2000/svg"><use xlink:href="/evil.svg#a"/></svg>), "not well-formed", "xlink")
    one_problem(%(<svg xmlns="http://www.w3.org/2000/svg"><use xlink:href="#a"/></svg>), "not well-formed", "xlink")
    one_problem(%(<svg xmlns="http://www.w3.org/2000/svg" x:onload="alert(1)"/>), "not well-formed", "onload")
    one_problem(%(<svg xmlns="http://www.w3.org/2000/svg"><x:script>alert(1)</x:script></svg>), "not well-formed")
    one_problem(%(<svg xmlns="http://www.w3.org/2000/svg" xmlns:q="urn:other"><use q:href="/evil.svg#a"/></svg>), "href")
  end

  test "an attribute is judged by its local part after the last colon, whatever the parser called it" do
    document = Nokogiri::XML(%(<svg xmlns="http://www.w3.org/2000/svg"><use xlink:href="/evil.svg#a" x:onclick="alert(1)"/></svg>))
    use = document.root.element_children.first
    found = use.attribute_nodes.map { |attribute| Theme::IconFile.attribute_problem(attribute, use, "a.svg") }

    assert_equal [ "xlink:href", "x:onclick" ], use.attribute_nodes.map(&:name), "libxml names an undeclared prefix's attribute whole"
    assert_includes found.first, "an address outside the icon"
    assert_includes found.last, "event handler"
  end

  # Inlined, the file is read again by the page's HTML parser, which takes a
  # paragraph out of the drawing and reads a comment, a CDATA section and a
  # processing instruction by rules of its own: each of these is a script
  # on the page that the XML parser saw as none.
  test "what the page's HTML parser reads otherwise than XML does is refused: an element that is no drawing, a comment that ends at once, CDATA and a processing instruction" do
    one_problem(svg(%(<p><iframe src="javascript:alert(1)"/></p>)), "<p>")
    one_problem(svg(%(<desc><img src="https://example.com/t.png"/></desc>)), "<img>")
    one_problem(svg(%(<path xmlns="urn:other" d="M0 0"/>)), "namespace")
    one_problem(svg(%(<s:path xmlns:s="http://www.w3.org/2000/svg" d="M0 0"/>)), "prefix")
    one_problem(svg("<!--><script>alert(1)</script>-->"), "comment")
    one_problem(svg("<!---><script>alert(1)</script>-->"), "comment")
    one_problem(svg("<desc><![CDATA[</desc><script>alert(1)</script>]]></desc>"), "CDATA")
    one_problem(svg("<?x ><script>alert(1)</script>?>"), "processing instruction")
    one_problem(svg(%(<a href="#g"><path d="M0 0"/></a>)), "<a>")
    one_problem(svg(%(<set attributeName="href" to="javascript:alert(1)"/>)), "<set>")
    one_problem(svg(%(<animate attributeName="href" values="javascript:alert(1)"/>)), "<animate>")
    one_problem(svg(%(<image href="#g" width="4" height="4"/>)), "<image>")
    one_problem(svg(%(<filter><feImage href="#g"/></filter>)), "<feImage>")

    assert_empty problems(svg(%(<!-- a note --><title>Arrow</title><g><path d="M0 0"/></g>))),
                 "a plain comment and a title are fine"
  end

  test "a file that is not there is refused, naming it, and nothing raises" do
    found = Theme::IconFile.problems(Pathname("/nonexistent/a.svg"), file: "assets/images/icons/a.svg")

    assert_equal 1, found.size
    assert found.first.start_with?("assets/images/icons/a.svg"), found.first
  end
end
