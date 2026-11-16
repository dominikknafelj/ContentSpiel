# A registered content type (spec §3.1 example: `blog`, `resume_entry`,
# `now_update`): adds the colour slot (`colour_index`), the two ViewComponents a `Post`
# of this type renders through (a whole listing and its own detail page,
# this sub-project's Task 4) and its starter content (what `db/seeds.rb` /
# `StarterContent` creates for a fresh install).
module ContentModel
  class ContentTypeDefinition < Definition
    # One post of the type (post types spec, §9.2): the values `Posts::Save`
    # takes (`body` Markdown, `fields` the type's typed fields) and `shows`,
    # texts the post's public detail page and its list hold. The shared tests'
    # posts, the canary and the starter content are all built from it.
    Sample = Data.define(:title, :excerpt, :body, :fields, :shows)

    METHOD_NAME = BlockTypeDefinition::METHOD_NAME

    # Every refusal of a declaration starts with the type's name, so a boot
    # that stops on a gem's type says whose it is.
    def refuse(message) = raise(ArgumentError, "#{name}: #{message}")
    private :refuse

    # A type only a built-in block type may declare (`FieldTypes::BLOCK_ONLY`):
    # a theme choice, a Mermaid source, a diagram's drawing.
    def refuse_type!(type)
      reason = FieldTypes::BLOCK_ONLY.dig(type, :posts)
      raise ArgumentError, "a content type may not declare a #{type} field: #{reason}" if reason
    end
    private :refuse_type!

    # The component drawing a whole listing of the type's posts, and the
    # methods its template may call: its line of the theme contract, a promise
    # to themes outside this repository. With no argument, the component.
    def list_component(component = nil, theme_methods: nil)
      return @list_component if component.nil?

      @list_component = component
      @list_theme_methods = checked_methods(:list_component, theme_methods)
      component
    end

    # The component drawing one post's own page; as `list_component`.
    def detail_component(component = nil, theme_methods: nil)
      return @detail_component if component.nil?

      @detail_component = component
      @detail_theme_methods = checked_methods(:detail_component, theme_methods)
      component
    end

    attr_reader :list_theme_methods, :detail_theme_methods

    # `{ component => theme_methods }` for the two components the type declares.
    def component_lines
      { list_component => list_theme_methods, detail_component => detail_theme_methods }.compact_blank
    end

    # The 1-based slot in CS Studio's six-hue content-type palette
    # (`Admin::Ui::ContentTypeDotComponent`; 7-12 are the same hues as rings, 13+
    # cycle). A plain accessor, not a `dsl_attribute`: it is assigned
    # (`type.colour_index = 4`), and `Registry#register` fills in a default
    # when a type states none.
    attr_accessor :colour_index

    # One sample post of the type. Checked once the whole type is declared
    # (`finalize!`), since it names the type's fields.
    def sample(**values)
      return @sample if values.empty?

      unknown = values.keys - Sample.members
      refuse "a sample holds title, excerpt, body, fields, shows; not #{unknown.join(", ")}" if unknown.any?

      @sample = Sample.new(title: values[:title], excerpt: values[:excerpt], body: values[:body],
                           fields: values[:fields] || {}, shows: Array(values[:shows]).freeze)
    end

    # The section page the starter content makes for the type; its post is the
    # type's sample. Read back via `starter_data`, not `starter`, since
    # `starter` itself takes the keyword that sets it.
    def starter(section:)
      @starter_section = section
    end

    # `{ section:, sample: }`, the sample being the values `Posts::Save` takes
    # (the sample without `shows`), or nil for a type with no starter.
    def starter_data
      return nil unless @starter_section

      { section: @starter_section,
        sample: { title: sample.title, excerpt: sample.excerpt, body: sample.body,
                  fields: sample.fields.presence }.compact }
    end

    # A Symbol naming a key under `admin.content_types.descriptions`, read
    # when the Settings card is drawn, never at registration: the locale files
    # may not be loaded then.
    def description(key = nil)
      return @description if key.nil?

      refuse "description is a Symbol naming a key under admin.content_types.descriptions: #{key.inspect}" unless key.is_a?(Symbol)

      @description = key
    end

    # A Symbol naming a key under `admin.content_types.groups`, the heading
    # the Settings card draws the type under; read when drawn.
    def group(key = nil)
      return @group if key.nil?

      refuse "group is a Symbol naming a key under admin.content_types.groups: #{key.inspect}" unless key.is_a?(Symbol)

      @group = key
    end

    def finalize!
      unless colour_index.nil?
        raise ArgumentError, "colour_index must be a positive integer" unless colour_index.is_a?(Integer) && colour_index >= 1
      end
      refuse "a starter needs a sample, the post it creates" if @starter_section && @sample.nil?
      check_sample! if @sample
    end

    private

    def checked_methods(which, names)
      refuse "#{which} declares `theme_methods:`, the methods its public template may call" if names.nil? || Array(names).empty?

      names = Array(names).map(&:to_s)
      bad = names.grep_v(METHOD_NAME)
      refuse "theme_methods takes a method's name, lowercase: #{bad.inspect}" if bad.any?

      names.freeze
    end

    def check_sample!
      sample = @sample
      refuse "a sample's title is a String, not blank" unless sample.title.is_a?(String) && sample.title.strip.present?
      refuse "a sample's excerpt is a String" unless sample.excerpt.nil? || sample.excerpt.is_a?(String)
      refuse "a sample's body is a Markdown String" unless sample.body.nil? || sample.body.is_a?(String)
      refuse "a sample's fields are a Hash" unless sample.fields.is_a?(Hash)

      undeclared = sample.fields.keys.map(&:to_s) - fields.map(&:name)
      refuse "a sample's fields name #{undeclared.join(", ")}, which the type does not declare" if undeclared.any?

      shows = sample.shows
      refuse "a sample's `shows:` names at least one text the public page holds for it, none of them blank" if shows.empty? || !shows.all?(String) || shows.any? { |text| text.strip.empty? }

      own = [ sample.title, sample.excerpt, *sample.fields.values ].grep(String)
      stray = shows - own
      refuse "a sample's `shows:` is its title, its excerpt or a String field value; #{stray.map(&:inspect).join(", ")} is none of them" if stray.any?
    end
  end
end
