module ContentModel
  # The registry of scalar field types. A field type is one entry here and
  # one input under `Admin::Fields` (`Admin::Fields::<Type>Field`, which also
  # answers `display`, how a value reads where it cannot be edited), and
  # nothing else branches on its name: `test/lib/field_type_branches_test.rb`
  # greps `app/` and `lib/` for every name registered here. The group types
  # (`:group`, `:groups`, `Definition::GROUP_TYPES`) are not scalar and are
  # not on it.
  #
  # Reset and filled first in `config/initializers/types.rb`'s `to_prepare`,
  # before any block type, content type or field group declares a field.
  module FieldTypes
    URL_SCHEMES = %w[http https mailto].freeze

    # Strictly `yyyy-mm-dd`: `Date.iso8601` alone also takes "20240101" and
    # week dates, which is not what the editor's placeholder promises.
    DATE_FORMAT = /\A\d{4}-\d{2}-\d{2}\z/

    # The name of the type whose list is the theme's. Named here once for the
    # two places that refuse it by kind of definition (a content type, a field
    # group, an outside block type) and so ask it of a field without a branch.
    THEME_CHOICE = :theme_choice
    THEME_CHOICE_LISTS = %i[section_styles icons].freeze

    # Types only a built-in block type may declare: choices for posts are not
    # built, and an outside type's list would need a key of theme.yml, which
    # the CMS owns.
    BLOCK_ONLY = [ THEME_CHOICE ].freeze

    # A link longer than this is refused, never cut.
    LINK_MAX = 2048

    # What no link holds, wherever it stands: white space (Unicode's too),
    # a control or invisible format character, a backslash.
    # The fragment of a same-page link (`#team`): what an element id the CMS
    # writes can hold. A Section's anchor (`BlockTypes::Section::ANCHOR`,
    # lowercase ASCII letters, digits and hyphens) is inside it, and so is a
    # heading's id (`Heading.id_from`: letters of any script, marks, digits,
    # underscores and hyphens). Nothing else: no `/`, `?`, `:`, `.`, `%` or `#`,
    # so a fragment is never read as a path, a query, a scheme or a second
    # fragment.
    LINK_FRAGMENT = /\A#[\p{L}\p{M}\p{N}_-]+\z/

    LINK_REFUSED = /[[:space:]\p{Cc}\p{Cf}\\]/

    # Text with its outer white space taken off, nil when nothing is left.
    STRIPPED = ->(value) { value.to_s.strip.presence }
    # The validation of a type with no rules of its own.
    NOTHING = ->(field:, value:, raw:, errors:, stored:, translations:) { }

    class << self
      def register(type)
        raise ArgumentError, "a field type is a ContentModel::FieldType, not #{type.inspect}" unless type.is_a?(FieldType)
        raise ArgumentError, "the field type #{type.name.inspect} is already registered" if types.key?(type.name)

        types[type.name] = type
      end

      def find(name) = types[name&.to_sym]

      def fetch(name)
        find(name) or raise KeyError, "unknown field type #{name.inspect} (known: #{names.join(", ")})"
      end

      def names = types.keys

      def all = types.values

      def reset! = types.clear

      # The twelve built-ins, in this order (it is `names`' order).
      def register_built_ins
        [ string, text, code, integer, boolean, date, url, select, content_type, tag, link, theme_choice ].each { |type| register(type) }
      end

      # The one rule for a link a visitor follows (the Card's address): an
      # http, https or mailto address, or a site-relative one, `/` and then
      # neither `/` nor a backslash. Browsers read a backslash as a slash and drop
      # tabs and line breaks inside an address, so "/<backslash>evil.example" and
      # "/\t/evil" are another host, "//evil" is one, and none of those
      # (nor any white space, control or invisible format character) is
      # accepted anywhere. A scheme is read case-insensitively. Total over
      # any value: a non-String is no link.
      #
      # A bare same-page anchor is accepted too, `#` and then at least one
      # character of `LINK_FRAGMENT`, so a card can jump to a section (or a
      # heading) of the page it is on. `#` alone, a fragment with a space, a
      # slash or any other character, and an anchor after an address
      # ("about#team" stays no link: a bare word) are refused.
      def link?(value)
        return false unless value.is_a?(String)
        value = value.dup.force_encoding(Encoding::UTF_8)
        return false unless value.valid_encoding? && value.length <= LINK_MAX
        return false if value.match?(LINK_REFUSED)
        return value.match?(%r{\A/(?![/\\])}) if value.start_with?("/")
        return value.match?(LINK_FRAGMENT) if value.start_with?("#")

        uri = URI.parse(value)
        scheme = uri.scheme.to_s.downcase
        return false unless URL_SCHEMES.include?(scheme)

        # An address with userinfo ("https://example.com@evil") reads as
        # one host and goes to another.
        scheme == "mailto" || (uri.host.present? && uri.userinfo.nil?)
      rescue URI::Error
        false
      end

      # What a `:link` field may hold: an address `link?` accepts, or a
      # reference to a page or a post (`LinkReference`). `link?` itself stays
      # the rule for what a browser may follow, so nothing that asks it can be
      # handed a reference to print.
      def link_value?(value) = link?(value) || LinkReference.parse(value).present?

      # What every type refuses that only a select, a content type field or
      # a string takes: a group field refuses it too (`Definition#field`).
      def refuse_choice_and_string_options(options)
        refuse_blank(options)
        refuse_control(options)
        refuse_string_options(options)
      end

      private

      def types = (@types ||= {})

      # -- The built-ins -------------------------------------------------

      def string
        FieldType.new(
          name: :string, cast: STRIPPED, translatable: true, audit: :value,
          options: lambda { |options, earlier|
            refuse_blank(options)
            refuse_control(options)
            # `help:` is a line under a string field in CS Studio (the Note
            # block's title: what an empty one does).
            raise ArgumentError, "`help:` is a line under a string field, written as a String" if options.key?(:help) && !(options[:help].is_a?(String) && options[:help].strip != "")
            # `placeholder_from:` names a select declared BEFORE the string,
            # whose chosen label is the string's placeholder.
            if options.key?(:placeholder_from)
              source = earlier.find { |candidate| candidate.name == options[:placeholder_from].to_s }
              raise ArgumentError, "`placeholder_from:` is for a string field and names a select field declared before it" unless source&.type == :select
            end
            raise ArgumentError, "`max:` on a string field is a number of characters, a positive Integer" if options.key?(:max) && !(options[:max].is_a?(Integer) && options[:max].positive?)
            raise ArgumentError, "`format:` on a string field is a Regexp, with `format_message:` the I18n key of the sentence that refuses a value" if options.key?(:format) && !(options[:format].is_a?(Regexp) && options[:format_message].is_a?(String))
            raise ArgumentError, "`format_message:` belongs to a `format:`" if options.key?(:format_message) && !options.key?(:format)
          },
          validate: lambda { |field:, value:, raw:, errors:, stored:, translations:|
            # A shape the whole value must have, refused with a sentence of its own.
            # An unchanged stored value is not this save's to refuse (a row written
            # around the service).
            pattern = field.options[:format]
            errors.add(field.name, :invalid, message: I18n.t(field.options[:format_message])) if pattern && value && value != stored && !pattern.match?(value)

            max = field.options[:max]
            next unless max

            errors.add(field.name, :too_long, count: max) if value && value.length > max
            # A translated string's limit in every language the object holds,
            # not only its own: a block's settings are validated in the
            # default language alone (`ContentBlock#settings_are_valid`), and
            # a German title would otherwise be stored at any length (note
            # block plan, ruling 2). One error per field, however many
            # languages are over.
            next unless field.translated?
            next if errors.added?(field.name, :too_long, count: max)

            over = translations.values.any? { |values| STRIPPED.call(values.to_h[field.name]).to_s.length > max }
            errors.add(field.name, :too_long, count: max) if over
          }
        )
      end

      def text = plain(:text, translatable: true)

      # Source code (code block spec §1) is kept as typed: the first line's
      # indentation, tabs, inner blank lines and trailing spaces. Two things
      # are not content: which line ending the browser sent (a form submits
      # CRLF) and lines of only white space before the first line and after
      # the last, which a paste brings along. Lines, not a regular
      # expression: a run of blank lines in the middle of 20,000 characters
      # must not be walked once per line. Never translated: the code is the
      # same in every language, and a translated field is what is offered to
      # an AI provider. `max:` counts characters. Audited as a digest: an
      # event's changes would hold the source twice beside the snapshot.
      def code
        FieldType.new(
          name: :code, translatable: false, audit: :digest,
          cast: lambda { |value|
            lines = value.to_s.gsub(/\r\n?/, "\n").split("\n", -1)
            lines.shift while lines.any? && lines.first.strip.empty?
            lines.pop while lines.any? && lines.last.strip.empty?
            lines.join("\n").presence
          },
          options: lambda { |options, _earlier|
            raise ArgumentError, "code fields can't be translated (the code is the same in every language)" if options[:translated]
            refuse_choice_and_string_options(options)
          },
          # The limit as its message says it: Rails' own `:too_long` with its
          # `count`, in the words of `errors.messages.code_too_long`
          # (config/locales/en.yml), which takes the limit grouped
          # ("20,000"), as the counter under the field writes it.
          validate: lambda { |field:, value:, raw:, errors:, stored:, translations:|
            max = field.options[:max]
            next unless value && max && value.length > max

            errors.add(field.name, :too_long, count: max, message: :code_too_long, limit: ActiveSupport::NumberHelper.number_to_delimited(max))
          }
        )
      end

      # `min:` and `max:` are a number's bounds. A non-blank input that is no
      # number casts to nil and is `:not_a_number`.
      def integer
        FieldType.new(
          name: :integer, translatable: false, audit: :value,
          cast: ->(value) { Integer(value.to_s, exception: false) },
          options: ->(options, _earlier) { refuse_choice_and_string_options(options) },
          validate: lambda { |field:, value:, raw:, errors:, stored:, translations:|
            next errors.add(field.name, :not_a_number) if value.nil? && raw.present?
            next if value.nil?

            errors.add(field.name, :greater_than_or_equal_to, count: field.options[:min]) if field.options[:min] && value < field.options[:min]
            errors.add(field.name, :less_than_or_equal_to, count: field.options[:max]) if field.options[:max] && value > field.options[:max]
          }
        )
      end

      def boolean
        FieldType.new(
          name: :boolean, translatable: false, audit: :value,
          cast: ->(value) { ActiveModel::Type::Boolean.new.cast(value) },
          options: ->(options, _earlier) { refuse_choice_and_string_options(options) },
          validate: NOTHING
        )
      end

      # A non-blank input that is no `yyyy-mm-dd` date casts to nil and is
      # `:invalid` (`FieldSet#assign` remembers it as a rejected input).
      def date
        FieldType.new(
          name: :date, translatable: false, audit: :value,
          cast: lambda { |value|
            next value if value.is_a?(Date)

            text = value.to_s.strip
            next nil unless text.match?(DATE_FORMAT)

            begin
              Date.iso8601(text)
            rescue ArgumentError, TypeError
              nil
            end
          },
          options: ->(options, _earlier) { refuse_choice_and_string_options(options) },
          validate: lambda { |field:, value:, raw:, errors:, stored:, translations:|
            errors.add(field.name, :invalid) if value.nil? && raw.present?
          }
        )
      end

      def url
        FieldType.new(
          name: :url, cast: STRIPPED, translatable: false, audit: :value,
          options: ->(options, _earlier) { refuse_choice_and_string_options(options) },
          validate: lambda { |field:, value:, raw:, errors:, stored:, translations:|
            errors.add(field.name, :invalid) if value && !url?(value)
          }
        )
      end

      # `options:` is the choices, a list of values or a Hash of value to
      # label. `blank:` labels the empty choice of a select that isn't
      # required; `control: :segmented` draws the choices as a row of
      # buttons, which has no button for an empty choice.
      def select
        FieldType.new(
          name: :select, cast: STRIPPED, translatable: false, audit: :value,
          options: lambda { |options, _earlier|
            raise ArgumentError, "select fields need `options:`" if options[:options].blank?
            check_blank(options)
            if options.key?(:control)
              check_control_value(options)
              raise ArgumentError, "`control: :segmented` has no button for a select's empty choice: it is for a select without `blank:`" if options.key?(:blank)
            end
            refuse_string_options(options)
          },
          validate: lambda { |field:, value:, raw:, errors:, stored:, translations:|
            choices = field.options[:options]
            errors.add(field.name, :inclusion) if value && !(choices.is_a?(Hash) ? choices.keys : Array(choices)).include?(value)
          }
        )
      end

      # A registered content type's name; `blank:` labels its empty choice
      # ("All types").
      def content_type
        FieldType.new(
          name: :content_type, cast: STRIPPED, translatable: false, audit: :value,
          options: lambda { |options, _earlier|
            check_blank(options)
            refuse_control(options)
            refuse_string_options(options)
          },
          validate: lambda { |field:, value:, raw:, errors:, stored:, translations:|
            errors.add(field.name, :inclusion) if value && ContentTypes.find(value).nil?
          }
        )
      end

      def tag = plain(:tag, translatable: false)

      # An address a visitor follows (see `link?`), or a well formed reference
      # to a page or a post (`LinkReference`), whatever the actor may read: the
      # editor shows the title only of what they may read, and a target that
      # is gone or was never there draws nothing. The same on every language,
      # so never translated.
      def link
        FieldType.new(
          name: :link, cast: STRIPPED, translatable: false, audit: :reference,
          options: lambda { |options, _earlier|
            raise ArgumentError, "link fields can't be translated (the address is the same in every language)" if options[:translated]
            refuse_choice_and_string_options(options)
          },
          validate: lambda { |field:, value:, raw:, errors:, stored:, translations:|
            errors.add(field.name, :invalid) if value && !link_value?(value)
          }
        )
      end

      # A name from one of the theme's lists (`of:`, one of THEME_CHOICE_LISTS).
      # The list is the theme's at the moment of the validation. A name the
      # record already stores stays valid whatever the theme declares now (a
      # theme that drops a style must not make every section that has it
      # unsaveable); only a NEW unknown name is refused. Never translated.
      def theme_choice
        FieldType.new(
          name: THEME_CHOICE, cast: STRIPPED, translatable: false, audit: :value,
          options: lambda { |options, _earlier|
            raise ArgumentError, "theme choice fields can't be translated (the name is the same in every language)" if options[:translated]
            unless THEME_CHOICE_LISTS.include?(options[:of]&.to_sym)
              raise ArgumentError, "theme choice fields need `of:` naming a list the theme declares: #{THEME_CHOICE_LISTS.join(", ")}"
            end
            refuse_choice_and_string_options(options)
          },
          validate: lambda { |field:, value:, raw:, errors:, stored:, translations:|
            next if value.nil? || value == stored
            next if ContentModel.theme_choices.call(field.options[:of].to_sym).any? { |entry| entry.name == value }

            errors.add(field.name, :inclusion)
          }
        )
      end

      # A type of stripped text with no rules of its own.
      def plain(name, translatable:)
        FieldType.new(
          name: name, cast: STRIPPED, translatable: translatable, audit: :value,
          options: ->(options, _earlier) { refuse_choice_and_string_options(options) },
          validate: NOTHING
        )
      end

      # -- Option rules several types share ------------------------------

      def refuse_blank(options)
        raise ArgumentError, "`blank:` names the empty choice of a select that isn't required" if options.key?(:blank)
      end

      def check_blank(options)
        raise ArgumentError, "`blank:` names the empty choice of a select that isn't required" if options.key?(:blank) && options[:required]
      end

      def check_control_value(options)
        raise ArgumentError, "`control:` is one of #{Definition::CONTROLS.map(&:inspect).join(", ")}" unless Definition::CONTROLS.include?(options[:control])
      end

      def refuse_control(options)
        return unless options.key?(:control)

        check_control_value(options)
        raise ArgumentError, "`control: :segmented` draws a select's choices as buttons: it is for a select"
      end

      def refuse_string_options(options)
        raise ArgumentError, "`help:` is a line under a string field, written as a String" if options.key?(:help)
        raise ArgumentError, "`placeholder_from:` is for a string field and names a select field declared before it" if options.key?(:placeholder_from)
        raise ArgumentError, "`format:` is for a string field" if options.key?(:format) || options.key?(:format_message)
      end

      def url?(value)
        URL_SCHEMES.include?(URI.parse(value).scheme.to_s.downcase)
      rescue URI::Error
        false
      end
    end
  end
end
