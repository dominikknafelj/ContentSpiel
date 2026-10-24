# A registered block type (spec §3.1 example: `post_list`, `image`, ...):
# adds the one thing a block needs beyond the shared `ContentModel::Definition`
# -- which ViewComponent renders it (`pages/show.html.erb`'s block dispatch,
# this sub-project's Task 4).
module ContentModel
  class BlockTypeDefinition < Definition
    dsl_attribute :component

    # A container type (`:container`, sections spec §3.1) says how many columns
    # a block of it has: a callable taking the block's `settings` hash and
    # answering an Integer. It is a callable, not a number, because the count
    # is a property of each block's own layout setting, and it lives on the
    # definition so that `ContentBlock#column_count` asks the type instead of
    # anything comparing a block's type with a name.
    dsl_attribute :columns

    # What a block type brings beside its fields (block types spec, decision
    # 1). Each declaration is READ by the list that used to repeat it by hand:
    # `theme_methods` and `tokens` by `Theme::Contract`, `stylesheet` by the
    # public stylesheet's build (`BlockTypes.theme_css_blocks`), `summary` by
    # the editor's tile, `read_only_actions` by the held form's allow-list,
    # `sample` by the shared tests. A declaration nothing reads would be
    # documentation in code; none of these is.

    # The capabilities something in the CMS asks for (`capability?`): a type
    # claiming another is refused at registration, since nothing would read it.
    CAPABILITIES = %i[container lists_posts].freeze

    # The count every tile's text, and a type's own tile line (`summary`), is
    # cut at. It lives here because a model may not name a component: the
    # tile (`Admin::EditorScreen::TileSummaryComponent::LENGTH`) and
    # `BlockTypes::Code`'s summary both read it.
    SUMMARY_LENGTH = 80

    # The icons a block type may name (contrast and buttons spec, C2 and
    # Ruling 6): each is a branch of CS Studio's icon partial
    # (`app/views/admin/shared/_icon.html.erb`, Lucide), which a model may
    # not name; `block_icon_component_test.rb` draws every one. A type names
    # one or none; an outside type picks from the same list. The last four
    # are the Note block's kinds (note block plan, rulings 11 and 12), which
    # its blocks' cards and tiles draw through `for_block:`.
    ICONS = %w[pilcrow image code_xml posts columns_2 info lightbulb circle_alert triangle_alert].freeze

    # The columns a block type may name with `uses`: the block card draws and
    # the save services write these four and no other (`BlockCardComponent`'s
    # template, `Admin::ContentBlocksController::TRANSLATED_COLUMNS`), so a
    # fifth name was silently drawn as nothing (decision 12).
    COLUMNS = %w[body caption alt image].freeze

    METHOD_NAME = /\A[a-z_][a-z0-9_]*\??\z/
    TOKEN_NAME = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
    ACTION = /\A[a-z0-9]+(?:-[a-z0-9]+)*(?:--[a-z0-9]+(?:-[a-z0-9]+)*)*#[a-zA-Z]\w*\z/

    # CSS Color 4's named colours (not `transparent`, not `currentcolor`,
    # which name no colour of their own).
    NAMED_COLOURS = %w[
      aliceblue antiquewhite aqua aquamarine azure beige bisque black blanchedalmond blue blueviolet brown burlywood
      cadetblue chartreuse chocolate coral cornflowerblue cornsilk crimson cyan darkblue darkcyan darkgoldenrod darkgray
      darkgreen darkgrey darkkhaki darkmagenta darkolivegreen darkorange darkorchid darkred darksalmon darkseagreen
      darkslateblue darkslategray darkslategrey darkturquoise darkviolet deeppink deepskyblue dimgray dimgrey dodgerblue
      firebrick floralwhite forestgreen fuchsia gainsboro ghostwhite gold goldenrod gray green greenyellow grey honeydew
      hotpink indianred indigo ivory khaki lavender lavenderblush lawngreen lemonchiffon lightblue lightcoral lightcyan
      lightgoldenrodyellow lightgray lightgreen lightgrey lightpink lightsalmon lightseagreen lightskyblue lightslategray
      lightslategrey lightsteelblue lightyellow lime limegreen linen magenta maroon mediumaquamarine mediumblue
      mediumorchid mediumpurple mediumseagreen mediumslateblue mediumspringgreen mediumturquoise mediumvioletred
      midnightblue mintcream mistyrose moccasin navajowhite navy oldlace olive olivedrab orange orangered orchid
      palegoldenrod palegreen paleturquoise palevioletred papayawhip peachpuff peru pink plum powderblue purple
      rebeccapurple red rosybrown royalblue saddlebrown salmon sandybrown seagreen seashell sienna silver skyblue
      slateblue slategray slategrey snow springgreen steelblue tan teal thistle tomato turquoise violet wheat white
      whitesmoke yellow yellowgreen
    ].freeze

    # An outside type's stylesheet holds no colour literal (decision 3). A
    # colour is looked for in a declaration's VALUE only, so a selector
    # (`#fade`, `li:has(#bead)`, `.red`) is never one: a declaration starts
    # after an opening brace or a semicolon. Comments are taken out of the
    # whole file first, and strings, `url()`s and custom property names
    # (`var(--th-red)`) out of each value. A word is bounded by anything but
    # a word character or a dash, so `red-pulse` holds no `red`. Refused: a
    # hex colour, a colour function (`color(` is not `color-mix(`, which is
    # allowed, though a literal inside it is not), and a named colour.
    DECLARATION = /[{;]\s*(?:--[\w-]+|-?[a-z][a-z-]*)\s*:\s*([^;{}]*)/i
    NOT_A_COLOUR = %r{"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|url\([^)]*\)|--[\w-]+}im
    COLOUR_LITERAL = /#\h{3,8}(?![\w-])|(?<![\w-])(?:rgba?|hsla?|hwb|lab|lch|oklab|oklch|color)\(|(?<![\w-])(?:#{NAMED_COLOURS.join("|")})(?![\w-])/i

    def self.colour_literal?(css)
      css.gsub(%r{/\*.*?\*/}m, " ").scan(DECLARATION).any? { |(value)| value.gsub(NOT_A_COLOUR, " ").match?(COLOUR_LITERAL) }
    end

    # One filled block of the type (decision 14): `settings` (string keys),
    # `translations` (locale => values: translated schema fields and the
    # `caption` / `alt` columns), `body` (Markdown, written in the default
    # language), `image` (true: the test attaches a library image), `shows`
    # (texts the public page holds for the block).
    Sample = Data.define(:settings, :translations, :body, :image, :shows)

    def initialize(name)
      super
      @themed_tokens = []
      @fixed_tokens = []
      @read_only_actions = []
    end

    attr_reader :themed_tokens, :fixed_tokens

    # Every refusal of a declaration starts with the type's name, so a boot
    # that stops on a gem's block type says whose it is.
    def refuse(message) = raise(ArgumentError, "#{name}: #{message}")
    private :refuse

    # The stylesheet the type brings: a String (or a Pathname, for an outside
    # type's absolute path) naming a .css file.
    def stylesheet(path = nil)
      return @stylesheet if path.nil?
      refuse "stylesheet is a path to a .css file, written as a String: #{path.inspect}" unless (path.is_a?(String) || path.is_a?(Pathname)) && path.to_s.strip != "" && path.to_s.end_with?(".css")

      @stylesheet = path
    end

    # The icon CS Studio draws for the type in the picker, on a card's head
    # and on a section's tile: one of `ICONS`, or none. `for_block:` is a
    # callable taking one block and answering one of `ICONS`: a block's card
    # and tile draw what it answers for that block, in place of the type's
    # (the Note block's kind; note block plan, ruling 12). The picker, which
    # has no block, draws the type's, so the type's should be the icon of
    # the value a new block starts with.
    def icon(name = nil, for_block: nil)
      return @icon if name.nil?
      refuse "icon is one of #{ICONS.join(", ")} (the icons CS Studio draws for a block type): #{name.inspect}" unless ICONS.include?(name.to_s)
      refuse "`icon for_block:` is a callable taking the block and answering one of #{ICONS.join(", ")}" unless for_block.nil? || for_block.respond_to?(:call)

      @icon_for_block = for_block
      @icon = name.to_s
    end

    # Whether a block's card and tile draw an icon of the block's own
    # (`for_block:`), which a save then has to redraw
    # (`Admin::ContentBlocksController#block_icon_streams`).
    def icon_follows_block? = !@icon_for_block.nil?

    # The icon one block of the type is drawn with: what `for_block:`
    # answers for it, else the type's own (nil for a type with none). A name
    # off the list raises, naming the list: only a built-in may declare
    # `for_block:` (`refuse_outside!`), so a wrong answer is this
    # repository's fault, and the name reaches the icon partial as a symbol,
    # never as markup.
    def icon_for(block)
      return @icon unless icon_follows_block? && block

      name = @icon_for_block.call(block).to_s
      refuse "its icon for a block is one of #{ICONS.join(", ")}: #{name.truncate(40).inspect}" unless ICONS.include?(name)

      name
    end

    def uses(*columns)
      unknown = columns.map(&:to_s) - COLUMNS
      refuse "a block type uses #{COLUMNS.join(", ")} and no other column; #{unknown.join(", ")} is drawn and saved by nothing" if unknown.any?

      super
    end

    # The methods the type's public template may call: the type's line in the
    # theme contract, a promise to themes outside this repository.
    def theme_methods(*names)
      return @theme_methods if names.empty?

      names = names.map(&:to_s)
      bad = names.grep_v(METHOD_NAME)
      refuse "theme_methods takes a method's name, lowercase: #{bad.inspect}" if bad.any?

      @theme_methods = names.freeze
    end

    # The `--th-` tokens the type brings, without the prefix: `themed` have a
    # value for light and one for dark, `fixed` have one.
    def tokens(themed: [], fixed: [])
      refuse "tokens are given as arrays of names (themed: [...], fixed: [...])" unless themed.is_a?(Array) && fixed.is_a?(Array)

      themed = themed.map(&:to_s)
      fixed = fixed.map(&:to_s)
      dups = (themed + fixed).tally.select { |_, n| n > 1 }.keys
      refuse "a token is declared once, as themed or as fixed: #{dups.inspect}" if dups.any?
      bad = (themed + fixed).grep_v(TOKEN_NAME)
      refuse "a token is named without the --th- prefix, in lowercase words joined by dashes: #{bad.inspect}" if bad.any?

      @themed_tokens = themed.freeze
      @fixed_tokens = fixed.freeze
    end

    # The tile's line of a closed block, as data: a callable taking the
    # block and `locale:` and answering parts (decision 8; the kinds are
    # `Admin::EditorScreen::TileSummaryComponent::LOOKS`).
    def summary(callable = nil)
      return @summary if callable.nil?
      refuse "`summary` is a callable taking the block and `locale:`" unless callable.respond_to?(:call) && takes_block_and_locale?(callable)

      @summary = callable
    end

    # The type's editor-script actions that only read or move focus: they
    # survive in a form someone else holds (decision 10).
    def read_only_actions(*ids)
      return @read_only_actions if ids.empty?

      ids = ids.map(&:to_s)
      refuse "a read-only action is declared once: #{ids.tally.select { |_, n| n > 1 }.keys.inspect}" if ids.uniq.size != ids.size
      bad = ids.grep_v(ACTION)
      refuse "a read-only action is written identifier#method (admin--editor--code-limit#update): #{bad.inspect}" if bad.any?

      @read_only_actions = ids.freeze
    end

    def sample(**values)
      return @sample if values.empty?

      unknown = values.keys - Sample.members
      refuse "a sample holds settings, translations, body, image, shows; not #{unknown.join(", ")}" if unknown.any?

      shows = Array(values[:shows])
      refuse "a sample's `shows:` names at least one text the public page holds for it, none of them blank" if shows.empty? || !shows.all?(String) || shows.any? { |text| text.strip.empty? }

      settings = values[:settings] || {}
      refuse "a sample's settings are a Hash" unless settings.is_a?(Hash)
      refuse "a sample's body is a Markdown String" unless values[:body].nil? || values[:body].is_a?(String)
      refuse "a sample's image is true or false" unless [ nil, true, false ].include?(values[:image])
      translations = values[:translations] || {}
      refuse "a sample's translations are a Hash of locale => Hash of values" unless translations.is_a?(Hash) && translations.values.all?(Hash)
      translations = translations.transform_keys(&:to_s)
      refuse "a sample's translations are written for \"en\" at least" if translations.any? && !translations.key?("en")

      @sample = Sample.new(
        settings: settings.transform_keys(&:to_s).freeze,
        translations: translations.freeze,
        body: values[:body],
        image: values[:image] == true,
        shows: shows.freeze
      )
    end

    # "gallery" for "gallery/album": an outside type's names are its owner's.
    def owner = name.include?("/") ? name.split("/", 2).first : nil

    def stylesheet_path(root: Rails.root)
      return nil if stylesheet.nil?

      path = Pathname(stylesheet)
      path.absolute? ? path : Pathname(root).join(ThemeCss::DEFAULT).dirname.join(path)
    end

    # The component's own template, found beside its source file, not
    # through ViewComponent's `sidecar_files` (`Theme#component_for` is the
    # one place that names that, `CLAUDE.md`). `theme:new` copies it; the
    # build scans the component's folder (`component_folder`), template or
    # not, when it is outside app/components/blocks.
    def component_template
      return nil unless component&.name

      file, = Object.const_source_location(component.name)
      template = file && Pathname(file).sub_ext(".html.erb")
      template if template&.file?
    end

    # The folder of the component's source file, template or not: what the
    # public stylesheet's build scans for an engine's utilities
    # (`BlockTypes.theme_css_blocks`), and what the public readers' guard
    # reads (test/lib/public_readers_test.rb). A component whose template is
    # inline (`erb_template`) has no file beside it and still has a folder.
    def component_folder
      return nil unless component&.name

      file, = Object.const_source_location(component.name)
      file && Pathname(file).dirname
    end

    # The tile calls `summary.call(block, locale:)`.
    def takes_block_and_locale?(callable)
      params = callable.respond_to?(:parameters) ? callable.parameters : callable.method(:call).parameters
      positional = params.any? { |kind, _| %i[req opt rest].include?(kind) }
      locale = params.any? { |kind, key| kind == :keyrest || (%i[key keyreq].include?(kind) && key == :locale) }
      positional && locale
    end
    private :takes_block_and_locale?

    # The `lists_posts` capability is a promise that `BlockTypes::PostList`
    # (today's only holder of it) can actually keep: `.listed_posts`/`.lists?`
    # read `settings.content_type`/`settings.tag` unconditionally, with no
    # guard of their own, because every *built-in* caller already declares
    # both fields. A type that claims the capability without them would only
    # find that out as a `NoMethodError` the first time a listing block
    # actually renders -- checked here instead, at registration, so a
    # developer error fails loudly at boot rather than at request time.
    #
    # The same goes for `:container`: `ContentBlock#column_count` calls
    # `columns` on every container block without a guard, so a container type
    # registered without it is refused here too.
    #
    # An outside type's own refusals come first (`refuse_outside!`): one
    # that claims `:lists_posts` is told it may not, rather than which
    # fields the claim would need.
    def finalize!
      refuse_outside! if owner
      unknown = capabilities - CAPABILITIES
      refuse "no reader of the CMS asks for the capability #{unknown.map(&:inspect).to_sentence}; a block type claims #{CAPABILITIES.map(&:inspect).to_sentence} and no other" if unknown.any?
      refuse "a container block type needs `columns`" if capability?(:container) && columns.nil?

      if capability?(:lists_posts)
        missing = %w[content_type tag] - fields.map(&:name)
        refuse "a lists_posts block type needs #{missing.join(' and ')} field(s)" if missing.any?
      end

      # Required of every block type (block types spec, decision 2): a theme
      # must be able to replace the public template, which needs its line in
      # the contract; and the sample is what puts the type into every shared
      # test, the canary above all.
      raise ArgumentError, "#{name}: a block type declares `theme_methods`, the methods its public template may call" if theme_methods.nil?
      raise ArgumentError, "#{name}: a block type declares a `sample`, one filled block of itself, for the shared tests" if sample.nil?
    end

    private

    # An outside type (a name with an owner) reaches only what has a seam
    # (block types spec, decisions 3 and 12): neither `:container`, which is
    # bound to the section classes and `BlockOutline`, nor `:lists_posts`,
    # bound to `BlockTypes::PostList`'s criteria, which decide posts'
    # addresses; tokens named after its owner, so two gems cannot claim one
    # name and none a built-in's; a stylesheet of its own, given as an
    # absolute path, whose colours are the theme's base tokens; and no
    # `read_only_actions`: the held form's allow-list is one list for every
    # form of the site (`HeldFields.allowed_actions`), an outside type has no
    # editor script of its own until step 2, so any action it named would be
    # one of the CMS's, kept alive in every held form. Step 2 opens it, with
    # the owner's prefix on the identifier. Nor `icon ... for_block:`, for the
    # reason written at its refusal. The
    # stylesheet is read here, once, at registration: one that is not there
    # stops the boot as this type's, not as a bare system error.
    def refuse_outside!
      %i[container lists_posts].each do |capability|
        refuse "a block type from outside may not claim :#{capability} (it has no seam for one yet)" if capability?(capability)
      end
      if read_only_actions.any?
        refuse "a block type from outside declares no read_only_actions yet: it brings no editor script of its own, and an " \
               "action it named would be one of the CMS's, kept in every held form of the site: #{read_only_actions.inspect}"
      end
      # A gem's callable would be asked on every card and tile of the editor,
      # where one that raised is a 500; the tile's rescue for a gem's
      # `summary` is not repeated for an icon until a gem asks for one.
      if icon_follows_block?
        refuse "a block type from outside names one icon for all its blocks: `icon for_block:` is the CMS's own yet, " \
               "because a callable that raised would fail every editor page holding a block of the type"
      end
      # A token name has no underscore (`TOKEN_NAME`), so `photo_gallery`'s
      # tokens start with `photo-gallery-`.
      prefix = "#{owner.tr("_", "-")}-"
      foreign = (themed_tokens + fixed_tokens).reject { |token| token.start_with?(prefix) }
      refuse "its tokens are named after its owner (#{prefix}…): #{foreign.inspect}" if foreign.any?
      return if stylesheet.nil?

      path = Pathname(stylesheet)
      refuse "a stylesheet from outside is an absolute path under its own root (Engine.root.join(...)): #{stylesheet}" unless path.absolute?
      source = begin
        path.read
      rescue SystemCallError => error
        refuse "its stylesheet #{path} cannot be read (#{error.class})"
      end
      # An import is resolved by the build and never read here, so its
      # colours would pass unseen: an outside type brings one file.
      refuse "its stylesheet imports another (@import); an outside type's styles are one file, read at registration" if source.gsub(%r{/\*.*?\*/}m, " ").match?(/@import\b/i)
      return unless self.class.colour_literal?(source)

      refuse "its stylesheet holds a colour literal; an outside type's colours are defined from the theme's " \
             "base tokens, as var() or color-mix() of them, so a theme that re-colours its base re-colours the block"
    end
  end
end
