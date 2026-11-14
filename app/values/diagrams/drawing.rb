require "digest"

module Diagrams
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
  # passes that rule, text only inside `TEXT_HOLDERS` (and nothing but text
  # inside `TEXT_ONLY`), and every name written is this file's own string.
  # Comments, whitespace between elements and the input's quoting are not
  # carried. So the HTML parser of the page that inlines it reads what the
  # XML parser read: no prefix, no comment, no CDATA and no element that
  # breaks out of an SVG into the page.
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
  #     `Diagrams::Source` keep a source that draws one from reaching Mermaid.
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
    # Bump when a list changes or what `#untitled_markup` writes does: the
    # public component's cache keeps a read under the rules and the markup it
    # was made with (`Blocks::DiagramComponent.cache_key`).
    REVISION = 1
    # A drawing scales down to its column to three fifths of its natural
    # width at most, where its 14px labels fall to about 9px; narrower, it
    # keeps that width and scrolls in its own box (`diagram.css` reads
    # `--diagram-min-width`, which `#untitled_markup` writes on the root).
    MIN_SCALE = 0.6

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

    # Elements that hold text and nothing else. An SVG `desc` (as `title`)
    # is an HTML integration point: the page's HTML parser reads what is in
    # it as HTML, where `<path/>` is no empty element, so an element inside
    # one would be a tree the page builds differently from the one written
    # here. Mermaid writes only text there.
    TEXT_ONLY = %w[desc].to_set.freeze

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

    # The values that say where to draw, each said with nothing but what its
    # attribute takes, so none can hold a quote, a colon, a slash or a word.
    NUMBER = /[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?/
    SEPARATOR = /(?:\s*,\s*|\s+)/
    # A coordinate, a length or a list of them (`points`, `viewBox`): numbers
    # with an optional unit, apart by a comma or whitespace.
    LENGTHS = /\A\s*(?:#{NUMBER}(?:px|em|ex|rem|pt|pc|cm|mm|in|%)?(?:#{SEPARATOR}#{NUMBER}(?:px|em|ex|rem|pt|pc|cm|mm|in|%)?)*)?\s*\z/
    # Path data: the path commands' letters, numbers and their separators.
    PATH_DATA = /\A[MmLlHhVvCcSsQqTtAaZzEe0-9.,+\-\s]*\z/
    # A transform list: SVG's six functions, each with numbers alone.
    TRANSFORM_FUNCTION = /(?:matrix|translate|scale|rotate|skewX|skewY)\s*\(\s*#{NUMBER}(?:#{SEPARATOR}#{NUMBER})*\s*\)/
    TRANSFORM = /\A\s*(?:#{TRANSFORM_FUNCTION}(?:#{SEPARATOR}?#{TRANSFORM_FUNCTION})*)?\s*\z/

    # A marker reference: the one `url(` a drawing may hold, to an id in it.
    REFERENCE = /\Aurl\(#([^()\s'"\\]+)\)\z/

    # The attributes that place a marker, each only as a REFERENCE to a
    # `marker` of this drawing. Mermaid writes the start and the end.
    MARKER_REFERENCES = %w[marker-start marker-mid marker-end].freeze

    # A value holding any of these is refused, whatever its attribute.
    UNSAFE = %r{javascript:|data:|//}i

    # An attribute's rule: `hosts`, the elements it may stand on (nil: any
    # allowed element), and `values`, a list or a pattern. The keyword lists
    # are SVG's own keywords for each, which only place text or a marker,
    # wider than the values Mermaid was seen writing.
    ATTRIBUTES = {
      **%w[x y x1 y1 x2 y2 cx cy r rx ry width height points viewBox dy].index_with { { hosts: nil, values: LENGTHS } },
      "d" => { hosts: nil, values: PATH_DATA },
      "transform" => { hosts: nil, values: TRANSFORM },
      "text-anchor" => { hosts: nil, values: %w[start middle end] },
      "dominant-baseline" => { hosts: nil, values: %w[auto middle central hanging alphabetic] },
      "alignment-baseline" => { hosts: nil, values: %w[auto baseline middle central hanging alphabetic] },
      "font-size" => { hosts: nil, values: /\A\d+(?:\.\d+)?(?:px)?\z/ },
      "font-weight" => { hosts: nil, values: [ "", "normal", "bold" ] },
      "font-style" => { hosts: nil, values: %w[normal italic] },
      **MARKER_REFERENCES.index_with { { hosts: %w[path line], values: REFERENCE } },
      **%w[markerWidth markerHeight refX refY].index_with { { hosts: %w[marker], values: LENGTHS } },
      # `strokeWidth`: the state diagram's `barbEnd` marker.
      "markerUnits" => { hosts: %w[marker], values: %w[userSpaceOnUse strokeWidth] },
      "orient" => { hosts: %w[marker], values: /\A(?:auto|auto-start-reverse|-?\d+(?:\.\d+)?)\z/ },
      "id" => { hosts: nil, values: /\A\S+\z/ },
      # Any value: the tokens that fail CLASS_TOKEN are dropped, and a class
      # left with none (`class=""` too) with them, as the frame drops it.
      "class" => { hosts: nil, values: /\A.*\z/m }
    }.freeze

    # On the root alone. Every type writes `aria-roledescription` (`flowchart-v2`, `er`, `pie`…).
    ROOT_ATTRIBUTES = { KEPT_ROOT_ARIA => { hosts: nil, values: CLASS_TOKEN } }.freeze

    # An id `#markup` is handed: the shape of the ids it writes.
    ID = /\A[A-Za-z][A-Za-z0-9_-]*\z/

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
    # the `<title>` written here (the block's description, as escaped text;
    # with `title: nil` no title and no name, for a drawing hidden from a
    # screen reader, which a pointer's tooltip would otherwise read),
    # described by Mermaid's `<desc>` when it has one, sized by its viewBox
    # (an inline SVG with no size fills its column) with its smallest width
    # (MIN_SCALE), and every id prefixed. Nil when the drawing fails on read.
    def markup(prefix:, title:, title_id:)
      untitled = untitled_markup(prefix: prefix, title_id: title_id)
      untitled && self.class.with_title(untitled, title: title, title_id: title_id)
    end

    # `#markup` with its `<title>` empty: a plain String, which the public
    # component caches by the stored drawing, since the title (the block's
    # description) changes on its own. Nil when the drawing fails on read.
    def untitled_markup(prefix:, title_id:)
      raise ArgumentError, "prefix #{prefix.inspect} is not the start of an id" unless prefix.match?(ID)
      raise ArgumentError, "title id #{title_id.inspect} is not an id" unless title_id.match?(ID)
      if title_id.start_with?("#{prefix}d-") || title_id == "#{prefix}desc"
        raise ArgumentError, "title id #{title_id.inspect} can be the name of a prefixed id of the drawing"
      end

      @untitled ||= {}
      return @untitled[[ prefix, title_id ]] if @untitled.key?([ prefix, title_id ])

      @untitled[[ prefix, title_id ]] = write_untitled(prefix: prefix, title_id: title_id)
    end

    # The markup written from a copy of the one parse (`parsed`): the copy is
    # changed, the parse is kept for the next read of this drawing.
    def write_untitled(prefix:, title_id:)
      document, reason = parsed
      return if reason

      document = document.dup
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
      root["style"] = "--diagram-min-width: #{number(width * MIN_SCALE)}px"
      root.prepend_child(document.create_element("title", id: title_id))

      self.class.serialize(document)
    end
    private :write_untitled

    # Writes the title's text into untitled markup's one empty `<title>`,
    # with no parse: the markup is this file's own serialisation, whose root
    # starts with that element and which holds no other `<title>` (Mermaid's
    # is dropped), and the title id is id-shaped.
    #
    # The one `html_safe` of the Diagram block: what it marks is this file's
    # own serialisation of a tree it built, and the title as escaped text.
    # Its input is `#untitled_markup`'s output as the public component reads
    # it back from `Rails.cache` (Solid Cache in production, a table of the
    # database), so that store is trusted as the database is; no other caller
    # hands it a string. It refuses one that is not an SVG root holding the
    # empty title once. A nil title takes the element and the root's
    # `aria-labelledby` out, so nothing names the drawing.
    def self.with_title(untitled, title:, title_id:)
      empty = %(<title id="#{title_id}"/>)
      labelled = %( aria-labelledby="#{title_id}")
      unless title_id.match?(ID) && untitled.to_s.start_with?("<svg ") && untitled.to_s.scan(empty).size == 1 && untitled.to_s.scan(labelled).size == 1
        raise ArgumentError, "the markup is not an SVG root with the empty title #{title_id.inspect}"
      end
      named = if title.nil? then untitled.sub(empty, "").sub(labelled, "")
      else untitled.sub(empty) { %(<title id="#{title_id}">#{ERB::Util.html_escape(title.to_s)}</title>) }
      end
      named.html_safe
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
        MARKER_REFERENCES.each do |name|
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
      # libxml's XML_ERR_UNDECLARED_ENTITY: `&name;` with no DTD to declare it.
      UNDECLARED_ENTITY = 26

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
        refuse :entity if error.code == UNDECLARED_ENTITY
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
        refuse :element if TEXT_ONLY.include?(to.name)
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
        when *MARKER_REFERENCES
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
      # and a reference to it, to anything not drawn or to anything but a
      # `marker`, is refused.
      def name_ids(root)
        renamed = {}
        [ root, *root.xpath(".//*[@id]") ].each do |element|
          next unless (old = element["id"])

          element["id"] = "d-#{renamed.size + 1}"
          renamed[old] = element
        end
        @references.each do |element, name, target|
          marker = renamed[target]
          refuse :url unless marker&.name == "marker"
          element[name] = "url(##{marker["id"]})"
        end
      end
    end
    private_constant :Cleaning
  end
end
