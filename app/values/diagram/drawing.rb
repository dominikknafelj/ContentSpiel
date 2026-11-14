require "digest"

module Diagram
  # A Diagram block's drawing: the SVG Mermaid drew in CS Studio's renderer
  # frame, and the one file that reads it. It is the security boundary of the
  # block. The editor's browser is not trusted, so every drawing it sends is
  # cleaned here before it is stored (`clean`), and cleaned again before a
  # public page prints it inline (`#markup`), so that a row written around
  # the services, or a drawing stored under looser rules, is held to today's.
  #
  # THE OUTPUT IS WRITTEN FROM THE PARSE TREE, never passed through from the
  # input string: an element is written only when its name is on `ELEMENTS`,
  # an attribute only when its name has a rule in `ATTRIBUTES` and its value
  # passes that rule, text only inside `TEXT_HOLDERS`, and every name written
  # is this file's own string. Comments, whitespace between elements and the
  # input's quoting are not carried. So the HTML parser of the page that
  # inlines it reads what the XML parser read: no prefix, no comment, no
  # CDATA and no element that breaks out of an SVG into the page.
  #
  # TWO OUTCOMES BESIDES A CLEAN DRAWING, as the spec divides them (Diagram
  # block spec, §3):
  #   - dropped quietly: what Mermaid writes in every drawing to paint it
  #     (its `<style>`, presentation attributes, `data-*`, the drop shadow and
  #     gradient defs, a class token that fails `CLASS_TOKEN`). The block's
  #     stylesheet paints by class instead, and none of it could be both
  #     harmless and themed, so refusing it would refuse every drawing;
  #   - refused, the whole drawing (`Result#reason`): whatever can fetch, run
  #     or link (a script, a foreignObject, an `<a>`, an image, `use`, SMIL,
  #     an `on*` handler, any `href`, `xml:base`, a `url()` that is not a
  #     marker in this drawing, a value holding `javascript:`, `data:` or
  #     `//`), and anything else no list names. A refusal is the frame and
  #     the server disagreeing, or a hand-made request: the line rules of
  #     `Diagram::Source` keep a source that draws one from reaching Mermaid.
  #   What is dropped is still looked through: an element inside a dropped
  #   one is refused when no list names it, and an attribute on it when it
  #   can fetch or run, so a `<symbol>` cannot carry a script past the walk.
  #
  # IDS ARE THE BLOCK'S OWN. A clean drawing's ids are `d-1`, `d-2`… in
  # document order, and every `url(#…)` follows; `#markup` prefixes them with
  # what the component hands it (the block and the language), so two
  # diagrams on a page, or a duplicated block, never share a marker. A clean
  # drawing cleans to itself.
  #
  # The renderer frame (`public/diagram-renderer.js`) drops the same things
  # with DOM APIs to measure the size the server will store, and refuses
  # nothing: its drop lists follow these, and this file is the authority.
  class Drawing
    # A full 10,000-character source draws about 770 KB once cleaned.
    MAX_BYTES = 1_048_576
    MAX_ELEMENTS = 5_000
    # Bump when a list changes: a cached read keeps the rules it was cleaned under.
    REVISION = 1

    # `svg` is the cleaned drawing, or nil with `reason`, a Symbol:
    # :not_xml :doctype :entity :processing_instruction :roots :element
    # :attribute :url :value :too_large :too_many_elements.
    Result = Data.define(:svg, :reason)

    SVG = "http://www.w3.org/2000/svg".freeze

    # A raw drawing carries what cleaning drops (Mermaid's styles, symbols and
    # data-*), so it is larger than its clean form; one past this cannot
    # clean to MAX_BYTES and is refused before it is parsed.
    MAX_INPUT_BYTES = 4 * MAX_BYTES

    # The elements a cleaned drawing may hold: what the seven types draw.
    # `svg` only as the root.
    ELEMENTS = %w[svg g defs marker path rect circle line polygon text tspan desc].index_by(&:itself).freeze

    # Dropped with everything in them. `style` only as the root's child,
    # where Mermaid writes it: anywhere else (inside `defs` included) it is
    # refused. `title` is Mermaid's `accTitle`: the block's description is the
    # drawing's name, and `#markup` writes the one title.
    DROPPED_ELEMENTS = %w[style filter feDropShadow linearGradient stop symbol title].to_set.freeze

    # The elements whose text is written; any other text is whitespace
    # between elements, or nothing an SVG draws.
    TEXT_HOLDERS = %w[text tspan desc].to_set.freeze

    # Mermaid's presentation, dropped from any element. `filter` points a
    # sequence diagram's boxes at the dropped `<filter>`'s drop shadow.
    DROPPED_ATTRIBUTES = %w[
      style fill stroke stroke-width stroke-dasharray opacity color font-family
      name fill-rule clip-rule transform-origin filter
    ].to_set.freeze

    # Dropped from the root, which `#markup` gives its role, name and size.
    # The root's `aria-roledescription` (the diagram's kind) is kept.
    DROPPED_ROOT_ATTRIBUTES = %w[width height style role].to_set.freeze
    KEPT_ROOT_ARIA = "aria-roledescription".freeze

    CLASS_TOKEN = /\A[A-Za-z][\w-]*\z/

    # A coordinate, a length, path data, a point list or a transform:
    # numbers, their units and the letters of path commands and transform
    # functions. No quote, colon, slash, backslash or semicolon, so a value
    # here can say nothing but where to draw.
    GEOMETRY = /\A[A-Za-z0-9.,+\-%() \t\r\n]*\z/

    # A marker reference: the one `url(` a drawing may hold, to an id in it.
    REFERENCE = /\Aurl\(#([^()\s'"\\]+)\)\z/

    # A value holding any of these is refused, whatever its attribute.
    UNSAFE = %r{javascript:|data:|//}i

    # An attribute's rule: `hosts`, the elements it may stand on (nil: any
    # allowed element), and `values`, a list or a pattern. The keyword lists
    # are SVG's own keywords for each, which only place text or a marker,
    # wider than the values Mermaid was seen writing.
    ATTRIBUTES = {
      **%w[x y x1 y1 x2 y2 cx cy r rx ry width height d points transform viewBox dy].index_with { { hosts: nil, values: GEOMETRY } },
      "text-anchor" => { hosts: nil, values: %w[start middle end] },
      "dominant-baseline" => { hosts: nil, values: %w[auto middle central hanging alphabetic] },
      "alignment-baseline" => { hosts: nil, values: %w[auto baseline middle central hanging alphabetic] },
      "font-size" => { hosts: nil, values: /\A\d+(?:\.\d+)?(?:px)?\z/ },
      "font-weight" => { hosts: nil, values: [ "", "normal", "bold" ] },
      "font-style" => { hosts: nil, values: %w[normal italic] },
      "marker-start" => { hosts: %w[path line], values: REFERENCE },
      "marker-end" => { hosts: %w[path line], values: REFERENCE },
      **%w[markerWidth markerHeight refX refY].index_with { { hosts: %w[marker], values: GEOMETRY } },
      # `strokeWidth`: the state diagram's `barbEnd` marker.
      "markerUnits" => { hosts: %w[marker], values: %w[userSpaceOnUse strokeWidth] },
      "orient" => { hosts: %w[marker], values: /\A(?:auto|auto-start-reverse|-?\d+(?:\.\d+)?)\z/ },
      "id" => { hosts: nil, values: /\A\S+\z/ },
      "class" => { hosts: nil, values: /./m }
    }.freeze

    # On the root alone. Every type writes `aria-roledescription` (`flowchart-v2`, `er`, `pie`…).
    ROOT_ATTRIBUTES = { KEPT_ROOT_ARIA => { hosts: nil, values: CLASS_TOKEN } }.freeze

    # An id `#markup` is handed: the shape of the ids it writes.
    ID = /\A[A-Za-z][\w-]*\z/

    SAVE = Nokogiri::XML::Node::SaveOptions::NO_DECLARATION | Nokogiri::XML::Node::SaveOptions::AS_XML

    def self.clean(svg)
      document, reason = read(svg)
      return Result.new(svg: nil, reason: reason) if reason

      Result.new(svg: serialize(document), reason: nil)
    end

    # The SHA-256 of a source as the frame takes it (`crypto.subtle`, UTF-8).
    def self.digest(source) = Digest::SHA256.hexdigest(source.to_s)

    # The cleaned document and nil, or nil and the reason.
    def self.read(svg)
      document = nil
      reason = catch(:refused) do
        document = Cleaning.new(svg.to_s).document
        nil
      end
      reason ? [ nil, reason ] : [ document, nil ]
    end

    def self.serialize(document) = document.root.to_xml(save_with: SAVE, encoding: "UTF-8")

    # `value` is the field's stored hash: `{ "svg" => String, "from" => hex }`,
    # `from` the digest of the source the frame drew.
    def initialize(value)
      @svg = value["svg"]
      @from = value["from"]
    end

    # Whether the drawing was made from this source; when not, it is the last
    # drawing that worked.
    def current?(source) = @from.present? && @from == self.class.digest(source)

    # Why the stored drawing fails on read, or nil when it passes.
    def reason = parsed.last

    def width = view_box&.at(2)
    def height = view_box&.at(3)

    # The drawing as a public page inlines it: the root an image named by
    # the `<title>` written here (the block's description, as escaped text),
    # described by Mermaid's `<desc>` when it has one, sized by its viewBox
    # (an inline SVG with no size fills its column), and every id prefixed.
    # Nil when the drawing fails on read.
    #
    # The one `html_safe` of the Diagram block: what it marks is this file's
    # own serialisation of a tree it built.
    def markup(prefix:, title:, title_id:)
      raise ArgumentError, "prefix #{prefix.inspect} is not the start of an id" unless prefix.match?(ID)
      raise ArgumentError, "title id #{title_id.inspect} is not an id" unless title_id.match?(ID)

      document, reason = self.class.read(@svg)
      return if reason

      root = document.root
      prefix_ids(root, prefix)
      root["role"] = "img"
      root["aria-labelledby"] = title_id
      if (desc = root.element_children.find { |child| child.name == "desc" })
        desc["id"] ||= "#{prefix}desc"
        root["aria-describedby"] = desc["id"]
      end
      root["width"] = number(width)
      root["height"] = number(height)

      heading = document.create_element("title", id: title_id)
      heading.content = title.to_s
      root.prepend_child(heading)

      self.class.serialize(document).html_safe
    end

    private

    def parsed = @parsed ||= self.class.read(@svg)

    def view_box
      document = parsed.first
      document && Cleaning.view_box(document.root["viewBox"])
    end

    def prefix_ids(root, prefix)
      [ root, *root.xpath(".//*") ].each do |element|
        element["id"] = "#{prefix}#{element["id"]}" if element["id"]
        %w[marker-start marker-end].each do |name|
          element[name] = element[name].sub("url(#", "url(##{prefix}") if element[name]
        end
      end
    end

    # At most three decimals, without trailing zeros.
    def number(value) = format("%.3f", value).sub(/\.?0+\z/, "")

    # One walk of one drawing: parses it, checks the document and writes the
    # clean tree. A refusal throws `:refused` with its reason.
    class Cleaning
      # [min-x, min-y, width, height] as Floats, or nil when the value is not
      # four numbers with a positive width and height.
      def self.view_box(value)
        parts = value.to_s.strip.split(/[\s,]+/)
        return unless parts.size == 4

        numbers = parts.map { |part| Float(part, exception: false) }
        numbers if numbers.all? { |number| number&.finite? } && numbers[2].positive? && numbers[3].positive?
      end

      # libxml's XML_ERR_DOCUMENT_END, "Extra content at the end of the document".
      DOCUMENT_END = 5

      attr_reader :document

      def initialize(text)
        text = text.dup.force_encoding(Encoding::UTF_8)
        refuse :not_xml unless text.valid_encoding?
        refuse :too_large if text.bytesize > MAX_INPUT_BYTES

        input = parse(text)
        check_document(input)
        @root = input.root
        @document = Nokogiri::XML::Document.new
        @document.encoding = "UTF-8"
        @ids = {}
        @references = []
        write
      end

      private

      def refuse(reason) = throw(:refused, reason)

      # Strict, with no network, no DTD loaded and no entity expanded. libxml
      # goes on after some errors (a prefix nobody declared, which it keeps
      # as part of the attribute's name): any error is a drawing that is not
      # well-formed.
      def parse(text)
        input = Nokogiri::XML(text, nil, "UTF-8") { |config| config.strict.nonet.nonoent.nodtdload }
        refuse :not_xml if input.errors.any? || input.root.nil?
        input
      rescue Nokogiri::XML::SyntaxError => error
        # libxml says a second root and text after the root alike.
        refuse :roots if error.code == DOCUMENT_END && Nokogiri::XML.fragment(text).element_children.size > 1
        refuse :not_xml
      end

      def check_document(input)
        if (dtd = input.internal_subset)
          refuse :entity if dtd.children.any? { |node| node.is_a?(Nokogiri::XML::EntityDecl) }
          refuse :doctype
        end
        refuse :processing_instruction if input.children.any? { |node| node.is_a?(Nokogiri::XML::ProcessingInstruction) }
        refuse :element unless input.root.name == "svg" && input.root.namespace&.href == SVG
      end

      def write
        root = @document.create_element(ELEMENTS.fetch("svg"))
        root.add_namespace_definition(nil, SVG)
        @document.root = root
        write_attributes(@root, root, root: true)
        refuse :value unless self.class.view_box(root["viewBox"])
        write_children(@root, root)
        name_ids(root)
        refuse :too_many_elements if root.xpath(".//*").size + 1 > MAX_ELEMENTS
        refuse :too_large if Drawing.serialize(@document).bytesize > MAX_BYTES
      end

      def write_children(from, to)
        from.children.each do |node|
          case node
          when Nokogiri::XML::Element then write_element(node, to)
          when Nokogiri::XML::Text then to.add_child(@document.create_text_node(node.content)) if TEXT_HOLDERS.include?(to.name)
          when Nokogiri::XML::ProcessingInstruction then refuse :processing_instruction
          when Nokogiri::XML::EntityReference then refuse :entity
          end
        end
      end

      def write_element(node, to)
        name = svg_name(node)
        if DROPPED_ELEMENTS.include?(name)
          refuse :element if name == "style" && node.parent != @root
          look_through(node)
          return
        end
        refuse :element unless ELEMENTS.key?(name) && name != "svg"

        element = @document.create_element(ELEMENTS.fetch(name))
        to.add_child(element)
        write_attributes(node, element, root: false)
        write_children(node, element)
        element.unlink if name == "g" && element.element_children.empty?
      end

      # A dropped element and everything in it: refused when it holds an
      # element no list names, a processing instruction, or an attribute
      # that could fetch or run.
      def look_through(node)
        node.traverse do |inner|
          case inner
          when Nokogiri::XML::Element
            name = svg_name(inner)
            known = (ELEMENTS.key?(name) || DROPPED_ELEMENTS.include?(name)) && name != "svg"
            refuse :element unless known && (name != "style" || inner == node)
            inner.attribute_nodes.each { |attribute| refuse :attribute if fetches?(attribute) }
          when Nokogiri::XML::ProcessingInstruction then refuse :processing_instruction
          when Nokogiri::XML::EntityReference then refuse :entity
          end
        end
      end

      # An element's name, when it is in SVG's namespace.
      def svg_name(node)
        refuse :element unless node.namespace&.href == SVG
        node.name
      end

      # A handler, a link or anything in another namespace (`xml:base`,
      # `xlink:href`): refused wherever it stands.
      def fetches?(attribute)
        name = attribute.name.downcase
        attribute.namespace || name.start_with?("on") || name == "href"
      end

      def write_attributes(node, element, root:)
        node.attribute_nodes.each do |attribute|
          refuse :attribute if fetches?(attribute)
          name = attribute.name
          next if dropped?(name, root)

          rule = (root && ROOT_ATTRIBUTES[name]) || ATTRIBUTES[name]
          refuse :attribute unless rule && (rule[:hosts].nil? || rule[:hosts].include?(element.name))
          write_attribute(element, name, attribute.value, rule[:values])
        end
      end

      def dropped?(name, root)
        DROPPED_ATTRIBUTES.include?(name) || name.start_with?("data-") ||
          (root && (DROPPED_ROOT_ATTRIBUTES.include?(name) || (name.start_with?("aria-") && name != KEPT_ROOT_ARIA)))
      end

      def write_attribute(element, name, value, values)
        refuse :url if value.match?(/url\(/i) && !(values == REFERENCE && value.match?(REFERENCE))
        refuse :value if value.match?(UNSAFE)
        refuse :value unless values.is_a?(Array) ? values.include?(value) : values.match?(value)

        case name
        when "id"
          refuse :value if @ids.key?(value)
          @ids[value] = element
          element["id"] = value
        when "marker-start", "marker-end"
          @references << [ element, name, value[REFERENCE, 1] ]
        when "class"
          tokens = value.split.grep(CLASS_TOKEN)
          element["class"] = tokens.join(" ") if tokens.any?
        else
          element[name] = value
        end
      end

      # `d-1`, `d-2`… in the order of the clean tree, then every marker
      # reference to the new name. An id on a `g` dropped as empty is gone,
      # and a reference to it, or to anything not drawn, is refused.
      def name_ids(root)
        renamed = {}
        [ root, *root.xpath(".//*[@id]") ].each do |element|
          next unless (old = element["id"])

          renamed[old] = element["id"] = "d-#{renamed.size + 1}"
        end
        @references.each do |element, name, target|
          refuse :url unless renamed.key?(target)
          element[name] = "url(##{renamed[target]})"
        end
      end
    end
    private_constant :Cleaning
  end
end
