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
    #
    # The columns a block type may name with `uses`: the block card draws and
    # the save services write these four and no other (`BlockCardComponent`'s
    # template, `Admin::ContentBlocksController::TRANSLATED_COLUMNS`), so a
    # fifth name was silently drawn as nothing (decision 12).
    COLUMNS = %w[body caption alt image].freeze

    METHOD_NAME = /\A[a-z_][a-z0-9_]*\??\z/
    TOKEN_NAME = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
    ACTION = /\A[a-z0-9]+(?:-[a-z0-9]+)*(?:--[a-z0-9]+(?:-[a-z0-9]+)*)*#[a-zA-Z]\w*\z/

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

    dsl_attribute :stylesheet

    def uses(*columns)
      unknown = columns.map(&:to_s) - COLUMNS
      raise ArgumentError, "a block type uses #{COLUMNS.join(", ")} and no other column; #{unknown.join(", ")} is drawn and saved by nothing" if unknown.any?

      super
    end

    # The methods the type's public template may call: the type's line in the
    # theme contract, a promise to themes outside this repository.
    def theme_methods(*names)
      return @theme_methods if names.empty?

      names = names.map(&:to_s)
      bad = names.grep_v(METHOD_NAME)
      raise ArgumentError, "theme_methods takes a method's name, lowercase: #{bad.inspect}" if bad.any?

      @theme_methods = names.freeze
    end

    # The `--th-` tokens the type brings, without the prefix: `themed` have a
    # value for light and one for dark, `fixed` have one.
    def tokens(themed: [], fixed: [])
      themed = themed.map(&:to_s)
      fixed = fixed.map(&:to_s)
      bad = (themed + fixed).grep_v(TOKEN_NAME)
      raise ArgumentError, "a token is named without the --th- prefix, in lowercase words joined by dashes: #{bad.inspect}" if bad.any?

      @themed_tokens = themed.freeze
      @fixed_tokens = fixed.freeze
    end

    # The tile's line of a closed block, as data: a callable taking the
    # block and `locale:` and answering parts (decision 8; the kinds are
    # `Admin::EditorScreen::TileSummaryComponent::LOOKS`).
    def summary(callable = nil)
      return @summary if callable.nil?
      raise ArgumentError, "`summary` is a callable taking the block and `locale:`" unless callable.respond_to?(:call)

      @summary = callable
    end

    # The type's editor-script actions that only read or move focus: they
    # survive in a form someone else holds (decision 10).
    def read_only_actions(*ids)
      return @read_only_actions if ids.empty?

      ids = ids.map(&:to_s)
      bad = ids.grep_v(ACTION)
      raise ArgumentError, "a read-only action is written identifier#method (admin--editor--code-limit#update): #{bad.inspect}" if bad.any?

      @read_only_actions = ids.freeze
    end

    def sample(**values)
      return @sample if values.empty?

      unknown = values.keys - Sample.members
      raise ArgumentError, "a sample holds settings, translations, body, image, shows; not #{unknown.join(", ")}" if unknown.any?

      shows = Array(values[:shows])
      raise ArgumentError, "a sample's `shows:` names at least one text the public page holds for it" if shows.empty? || !shows.all?(String)

      translations = (values[:translations] || {}).transform_keys(&:to_s)
      raise ArgumentError, "a sample's translations are written for \"en\" at least" if translations.any? && !translations.key?("en")

      @sample = Sample.new(
        settings: (values[:settings] || {}).transform_keys(&:to_s).freeze,
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
    # one place that names that, `CLAUDE.md`). `theme:new` copies it and the
    # build scans its folder when it is outside app/components/blocks.
    def component_template
      file, = component && Object.const_source_location(component.name)
      file && Pathname(file).sub_ext(".html.erb")
    end

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
    # And for `:code`: the editor's tile asks a block of such a type for its
    # `filename`, its `code` and its `language` by name
    # (`Admin::EditorScreen::TileSummaryComponent#code_line`), so a type that
    # claims the capability without all three was a `NoMethodError` in the
    # page editor the first time a block of it sat in a section.
    def finalize!
      raise ArgumentError, "a container block type needs `columns`" if capability?(:container) && columns.nil?

      if capability?(:lists_posts)
        missing = %w[content_type tag] - fields.map(&:name)
        raise ArgumentError, "a lists_posts block type needs #{missing.join(' and ')} field(s)" if missing.any?
      end

      if capability?(:code)
        missing = %w[language filename code] - fields.map(&:name)
        raise ArgumentError, "a code block type needs #{missing.join(' and ')} field(s)" if missing.any?
      end
    end
  end
end
