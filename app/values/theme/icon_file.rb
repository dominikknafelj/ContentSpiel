class Theme
  # An icon file a theme declares in theme.yml (`Theme::Declarations`), and
  # the one way the public site draws it: inlined, so a theme colours it
  # with its own stylesheet (`currentColor`, its classes, a gradient its
  # layout defines).
  #
  # A FENCE, NOT A SANITISER. A theme is trusted as the deployment is
  # (theming, "Checking a folder"), and the check refuses what an icon has
  # no business holding; it does not rewrite the file, and `inline` changes
  # nothing but two attributes on the root. A sanitiser would be a promise of
  # safety a fence does not make, and it would change the drawing. So a
  # theme's own icon keeps what it is drawn with: its own stroke, filled
  # shapes, layers with classes, its own `width`, `height` and `viewBox`,
  # and `url(#…)` references to what the theme's layout defines.
  #
  # TWO PARSERS READ THE FILE, and the fence has to hold for both. It is
  # checked as XML, here; it is inlined into an HTML page, whose parser
  # reads the same text by rules of its own: it lowercases names
  # (`<SCRIPT>` is a script there), reads a prefix as part of the name and
  # `xlink:href` as XLink's whatever the file bound the prefix to, takes a
  # paragraph or an image out of the drawing into the page (and with it
  # whatever attribute it carries), ends a comment at `<!-->`, and ends a
  # CDATA section or a processing instruction at their first `>`. So every
  # name is compared lowercased and by its local part, whatever its prefix
  # or namespace; every element is one of SVG's drawing elements, in SVG's
  # namespace and unprefixed (so both parsers see the same element); and a
  # comment that the HTML parser would end at once, CDATA and a processing
  # instruction are refused.
  #
  # NO ID, in any icon: an icon drawn twice on a page would repeat it, and a
  # reference meant for the layout's gradient could find the icon's
  # instead. A reference names what the theme's layout defines.
  module IconFile
    MAX_BYTES = 32_768
    SVG = "http://www.w3.org/2000/svg".freeze

    # What may not be in an icon at all, by its lowercased local name, with
    # the name it is said by.
    FORBIDDEN = { "script" => "script", "foreignobject" => "foreignObject", "style" => "style" }.freeze

    # SVG's elements an icon is drawn with, lowercased: shapes, groups and
    # references, text, paint servers and filter primitives. Not an `a`, an
    # `image` or `feImage` (each fetches or follows an address), no
    # animation (`set` and `animate` can write an address into an
    # attribute), no `switch` and no `metadata` (which hold other XML).
    DRAWING = %w[
      svg g defs symbol use title desc
      path circle ellipse line polyline polygon rect
      text tspan textpath
      lineargradient radialgradient stop pattern clippath mask marker
      filter feblend fecolormatrix fecomponenttransfer fecomposite feconvolvematrix fediffuselighting
      fedisplacementmap fedistantlight fedropshadow feflood fefunca fefuncb fefuncg fefuncr fegaussianblur
      femerge femergenode femorphology feoffset fepointlight fespecularlighting fespotlight fetile feturbulence
    ].to_set.freeze

    # A paint, a filter or a clip in an attribute names a fragment and
    # nothing else: `url(#glow)`, quoted or not.
    URL = /url\s*\(/i
    FRAGMENT_URL = /url\(\s*(["']?)#[A-Za-z_][\w.:-]*\1\s*\)/i
    PREDEFINED = %w[amp lt gt quot apos].freeze
    ENTITY = /&([A-Za-z_:][\w.:-]*);/
    DECLARED_ENCODING = /\A﻿?<\?xml\s[^>]*?\bencoding\s*=\s*["']([^"']*)["']/

    # Whatever is before and after the root in a file that passed: the XML
    # declaration, comments and white space (a comment holds no `--`, so
    # `<!--` cannot start inside one).
    PROLOG = /\A﻿?(?:<\?xml\s(?:(?!\?>).)*\?>)?(?:\s|<!--(?:(?!--).)*-->)*/m
    EPILOG = /(?:\s|<!--(?:(?!--).)*-->)*\z/m
    ROOT_TAG = /\A<svg((?:\s+[^\s=\/>]+\s*=\s*(?:"[^"]*"|'[^']*'))*)\s*\/?>/
    ADDED = { "aria-hidden" => "true", "focusable" => "false" }.freeze

    module_function

    # The problems of the file at `path`, each a sentence that starts with
    # `file` (how the theme's author knows the file) and says what to do.
    def problems(path, file:)
      size = File.size(path)
      return [ "#{file} is larger than #{MAX_BYTES / 1024} KB, which is more than an icon needs. Simplify the drawing." ] if size > MAX_BYTES

      problems_in(File.binread(path), file: file)
    rescue SystemCallError => error
      [ "#{file} cannot be read (#{error.message.split(" @ ").first}). Check that the file is there and readable." ]
    end

    # The same for the bytes themselves: what `Theme#icon_svg` asks of the
    # bytes it is about to inline, so what is drawn is what was fenced.
    def problems_in(source, file:)
      source = source.to_s
      return [ "#{file} is larger than #{MAX_BYTES / 1024} KB, which is more than an icon needs. Simplify the drawing." ] if source.bytesize > MAX_BYTES

      text = source.dup.force_encoding(Encoding::UTF_8)
      declared = text.valid_encoding? && text[DECLARED_ENCODING, 1]
      if !text.valid_encoding? || (declared && !declared.casecmp?("utf-8"))
        return [ "#{file} is not UTF-8 text, which is what the page it is drawn on is. Save the file as UTF-8." ]
      end

      document = parse(text, file)
      return [ document ] if document.is_a?(String)

      if document.internal_subset
        return [ "#{file} has a DOCTYPE, which an icon may not: a DOCTYPE can declare entities. Take it out." ]
      end

      root = document.root
      unless root.name == "svg" && root.namespace&.href == SVG
        return [ "#{file}: the root must be an <svg> element in SVG's namespace (xmlns=\"#{SVG}\"), not <#{qualified(root)}>. " \
                 "Make the file one svg element." ]
      end
      return [ "#{file}: the root <#{qualified(root)}> has a prefix, which the page's HTML does not read as an svg. Write it as <svg xmlns=\"#{SVG}\">." ] if root.namespace.prefix

      walk(document, file)
    end

    # The file as it is drawn on the page: from its root's start tag to its
    # end tag, with `aria-hidden="true"` and `focusable="false"` on the root
    # (an icon is decoration: the text beside it says what it is), where the
    # root does not already carry the attribute. Nothing else is changed.
    # Asked only of a file that passed the fence.
    def inline(source)
      text = source.to_s.dup.force_encoding(Encoding::UTF_8)
      body = text.sub(PROLOG, "")
      body = body.sub(EPILOG, "")
      tag = body[ROOT_TAG, 1] or raise ArgumentError, "inline is asked of a file that passed the fence: this one has no <svg> root"

      written = tag.scan(/\s([^\s=\/>]+)\s*=/).flatten.map(&:downcase)
      added = ADDED.reject { |name, _| written.include?(name) }.map { |name, value| %( #{name}="#{value}") }.join
      body.sub(/\A<svg/, "<svg#{added}")
    end

    # `strict` raises on a fatal error only. libxml says a prefix nobody
    # declared (`xlink:href` without `xmlns:xlink`) as an error it goes on
    # after, naming the attribute `xlink:href` in no namespace, while the
    # page's HTML parser reads it as XLink's href: so any error is a file
    # that is not well-formed.
    def parse(text, file)
      document = Nokogiri::XML(text) { |config| config.strict.nonet }
      error = document.errors.first
      return document unless error

      "#{file} is not well-formed XML (#{said(error)}). Correct it, or export the icon again."
    rescue Nokogiri::XML::SyntaxError => error
      if text.match?(/<!DOCTYPE/i)
        "#{file} has a DOCTYPE, which an icon may not: a DOCTYPE can declare entities. Take it out."
      elsif (entity = text.scan(ENTITY).flatten.find { |name| !PREDEFINED.include?(name) })
        "#{file} uses the entity &#{entity};, which an icon may not. Write the character itself, or a character reference (&#x2014;)."
      else
        "#{file} is not well-formed XML (#{said(error)}). Correct it, or export the icon again."
      end
    end

    # libxml's sentence without its own place and level ("1:70: ERROR: ").
    def said(error)
      words = error.message.strip.split("\n").first.to_s.sub(/\A\d+:\d+:\s*(?:FATAL|ERROR|WARNING):\s*/, "")
      error.line.to_i.positive? ? "line #{error.line}: #{words}" : words
    end

    # Every node, without recursion. One problem per node and per
    # attribute: the first thing found that it may not be.
    def walk(document, file)
      found = []
      stack = document.children.to_a.reverse
      until stack.empty?
        node = stack.pop
        problem = node_problem(node, file)
        found << problem if problem
        # A refused element is said once, and not what is inside it.
        next if problem || !node.element?

        found.concat(node.attribute_nodes.filter_map { |attribute| attribute_problem(attribute, node, file) })
        stack.concat(node.children.to_a.reverse)
      end
      found
    end

    def node_problem(node, file)
      if node.comment?
        if node.content.start_with?(">", "->")
          "#{file} has a comment that begins with #{node.content[0, 2].inspect}, which the page's HTML ends at once and reads the rest as markup. Take the comment out."
        end
      elsif node.cdata?
        "#{file} has a CDATA section, which the page's HTML reads by rules of its own. Write its text as plain text, or take it out."
      elsif node.processing_instruction?
        "#{file} has a processing instruction (<?#{node.name} …?>), which an icon has no use for. Take it out."
      elsif node.element?
        element_problem(node, file)
      end
    end

    def element_problem(node, file)
      name = node.name.downcase
      if FORBIDDEN.key?(name)
        "#{file} holds a <#{FORBIDDEN[name]}> element, which an icon may not. Take it out; a theme's styles go in its stylesheet."
      elsif !DRAWING.include?(name)
        "#{file} holds a <#{qualified(node)}> element, which is no part of an icon: an icon is drawn with SVG's shapes, groups, " \
          "text, gradients and filters, and nothing that fetches, follows or animates an address. Take it out."
      elsif node.namespace&.href != SVG
        "#{file}: <#{qualified(node)}> is not in SVG's namespace (#{node.namespace&.href || "none"}), so the page draws something else. " \
          "Take its xmlns out, so it is SVG's."
      elsif node.namespace.prefix
        "#{file}: <#{qualified(node)}> has a prefix, which the page's HTML does not read as SVG. Write it without one (<#{node.name}>)."
      end
    end

    # Judged by the local part after the last colon, whatever the parser
    # called the attribute, as the page's HTML parser reads `xlink:href`.
    def attribute_problem(attribute, node, file)
      name = attribute.name.split(":").last.to_s.downcase
      value = attribute.value
      where = "#{file}: the attribute #{qualified(attribute)} on <#{qualified(node)}>"
      if name.start_with?("on")
        "#{where} is an event handler, which an icon may not have. Take it out."
      elsif name == "id"
        "#{where} is an id, which no icon may have: an icon drawn twice repeats it. Take it out; to paint with a gradient, " \
          "define it in the theme's layout and name it with url(#…)."
      elsif name == "style"
        "#{where} is a style attribute, which an icon may not have. Write it as presentation attributes (fill, stroke) or a class " \
          "the theme's stylesheet draws."
      elsif name == "href" && !value.start_with?("#")
        "#{where} is #{value.truncate(40).inspect}, an address outside the icon. An href may only name a fragment (#name): take it out."
      elsif value.include?("\\")
        "#{where} holds a backslash, which CSS reads as an escape. Take it out."
      elsif value.scan(URL).size != value.scan(FRAGMENT_URL).size
        "#{where} holds a url( that names an address or data, not a fragment. A url() may only name what the theme's layout " \
          "defines: url(#name)."
      end
    end

    def qualified(node)
      prefix = node.namespace&.prefix
      prefix ? "#{prefix}:#{node.name}" : node.name
    end
  end
end
