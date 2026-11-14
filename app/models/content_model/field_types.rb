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

    # Types only a built-in block type may declare, each with why a post
    # type (or a field group) and an outside block type may not: choices for
    # posts are not built, and an outside type's list would need a key of
    # theme.yml, which the CMS owns; a Mermaid source and its drawing are
    # the Diagram block's, whose card makes the drawing (the renderer frame)
    # and whose component prints it, and no other record has either.
    DIAGRAM_ONLY = "a drawing is made by the Diagram block's card and printed by its component, and nothing else draws or shows one".freeze
    BLOCK_ONLY = {
      THEME_CHOICE => { posts: "choices for posts are not built", outside: "its list would need a key of theme.yml, which the CMS owns" },
      mermaid: { posts: DIAGRAM_ONLY, outside: DIAGRAM_ONLY },
      diagram_drawing: { posts: DIAGRAM_ONLY, outside: DIAGRAM_ONLY }
    }.freeze

    # A link longer than this is refused, never cut.
    LINK_MAX = 2048

    # An address longer than this is refused, never cut (RFC 5321: 254).
    EMAIL_MAX = 254

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

    # Text kept as typed (code block spec §1), for `:code` and `:mermaid`:
    # the line endings as one `\n` and the lines of only white space before
    # the first line and after the last dropped, nil when nothing is left.
    # Lines, not a regular expression: a run of blank lines in the middle of
    # 20,000 characters must not be walked once per line.
    TYPED_TEXT = lambda do |value|
      lines = value.to_s.gsub(/\r\n?/, "\n").split("\n", -1)
      lines.shift while lines.any? && lines.first.strip.empty?
      lines.pop while lines.any? && lines.last.strip.empty?
      lines.join("\n").presence
    end

    # What a `:diagram_drawing` cast answers for a value that does not clean:
    # a mark its validation refuses (`:invalid_drawing`), never a nil, which
    # `FieldSet#assign` would drop without a word. It is never stored, since
    # the save it is in is refused.
    DRAWING_REFUSED = "refused".freeze

    # A drawing's `from`: the SHA-256 of its source in hex, which is all it
    # is ever compared with (`Diagrams::Drawing#current?`). Anything else,
    # a hand-posted string of any length among them, is refused as the
    # drawing's shape, so it never rides along with every later save.
    DRAWING_FROM = /\A\h{64}\z/

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

      # The sixteen built-ins, in this order (it is `names`' order).
      def register_built_ins
        [ string, text, code, mermaid, diagram_drawing, integer, boolean, date, url, select, content_type, tag, link, theme_choice, email, form ].each { |type| register(type) }
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
            raise ArgumentError, "`drawing:` is a mermaid field's, naming its diagram_drawing field" if options.key?(:drawing)
            raise ArgumentError, DESCRIPTION_REFUSAL if options.key?(:description)
            # `help:` is a line under a string field in CS Studio (the Note
            # block's title: what an empty one does).
            check_help(options)
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

      # Stripped prose. `max:` (a positive Integer) counts characters and is
      # refused in the words of the code field's limit (`errors.messages
      # .code_too_long`), `:too_long` with its `count`: a form's long text
      # (`Forms::BuiltInFieldTypes`) is limited, and the editors' own text
      # fields are not unless they say so. A translated text's other
      # languages are not looked at: the one caller with a limit is untranslated.
      # `help:` is a line under it in CS Studio, as under a string (the
      # Diagram block's description: what it is for).
      def text
        FieldType.new(
          name: :text, cast: STRIPPED, translatable: true, audit: :value,
          options: lambda { |options, _earlier|
            raise ArgumentError, "`max:` on a text field is a number of characters, a positive Integer" if options.key?(:max) && !(options[:max].is_a?(Integer) && options[:max].positive?)
            check_help(options)
            refuse_choice_and_string_options(options.except(:max, :help))
          },
          validate: lambda { |field:, value:, raw:, errors:, stored:, translations:|
            max = field.options[:max]
            next unless value && max && value.length > max

            errors.add(field.name, :too_long, count: max, message: :code_too_long, limit: ActiveSupport::NumberHelper.number_to_delimited(max))
          }
        )
      end

      # One plain address (`MailSettings.one_address?`, the rule the sender
      # address is held to: no name, no list, no angle brackets), at most
      # `EMAIL_MAX` characters. The same on every language, so never
      # translated. A form's email field (`Forms::BuiltInFieldTypes`) is the
      # first user; the address reaches a mail's Reply-To, which the mail gem
      # raises on when it is not one address.
      def email
        FieldType.new(
          name: :email, cast: STRIPPED, translatable: false, audit: :value,
          options: lambda { |options, _earlier|
            raise ArgumentError, "email fields can't be translated (an address is the same in every language)" if options[:translated]
            refuse_choice_and_string_options(options)
          },
          validate: lambda { |field:, value:, raw:, errors:, stored:, translations:|
            next unless value

            if value.length > EMAIL_MAX
              errors.add(field.name, :too_long, count: EMAIL_MAX)
            elsif !MailSettings.one_address?(value)
              errors.add(field.name, :invalid)
            end
          }
        )
      end

      # A visitor's form, named by its id (the Form block's one field): a String of digits, as `Forms::Placements` compares it
      # with `settings ->> 'form_id'`, else nothing. Which form that is, and
      # whether it is kept, is asked where the block is drawn (a trashed or
      # missing form draws nothing) and in CS Studio's select, which names a
      # stored form that is gone; it is not refused here, because the content
      # model sits below the forms and knows none of them, and a form trashed
      # after it was placed must not make the page's other blocks unsaveable.
      # The same in every language, so never translated.
      def form
        FieldType.new(
          name: :form, translatable: false, audit: :value,
          cast: ->(value) { value.to_s.strip.then { |text| text.match?(/\A[1-9]\d*\z/) ? text : nil } },
          options: lambda { |options, _earlier|
            raise ArgumentError, "form fields can't be translated (a form is the same in every language)" if options[:translated]
            refuse_choice_and_string_options(options)
          },
          validate: NOTHING
        )
      end

      # Source code (code block spec §1) is kept as typed: the first line's
      # indentation, tabs, inner blank lines and trailing spaces. Two things
      # are not content: which line ending the browser sent (a form submits
      # CRLF) and lines of only white space before the first line and after
      # the last, which a paste brings along (`TYPED_TEXT`). Never translated: the code is the
      # same in every language, and a translated field is what is offered to
      # an AI provider. `max:` counts characters. Audited as a digest: an
      # event's changes would hold the source twice beside the snapshot.
      def code
        FieldType.new(
          name: :code, translatable: false, audit: :digest, cast: TYPED_TEXT,
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

      # A Diagram block's Mermaid source (Diagram block spec §1 and §5), cast
      # as `:code` is. The editor's script hashes the same normalised text for
      # the drawing's `from` (`Diagrams::Drawing.digest`), so a drawing is
      # current for the source as stored. Unlike code it may be translated,
      # and like code it is never offered to an AI provider. `max:` counts
      # characters, and the source's own limit
      # (`Diagrams::Source::MAX_CHARACTERS`) holds without one; both are
      # refused in the Code field's words, and the length is all a save is
      # refused for. A source with a line `Diagrams::Source` refuses (a
      # `classDef`, a `click`, a type off the list) is stored as typed, as any
      # half-typed source is: the line rules are the editor's and the frame's,
      # which say the line's sentence and draw nothing from it, so the drawing
      # stays the last that worked. Mermaid never runs on the server, the
      # frame refuses such a source before Mermaid sees it, and what reaches a
      # page is a drawing `Diagrams::Drawing` cleaned. A block's settings are
      # validated in the default language alone
      # (`ContentBlock#settings_are_valid`), so every language the object
      # holds is read here, each sentence once.
      #
      # `drawing:` names the `:diagram_drawing` field its drawing is written
      # into, translated as the source is.
      # `description:`, if given, names the string or text field that
      # describes the drawing, translated as the source is: the card says the
      # site shows nothing while it is blank.
      def mermaid
        FieldType.new(
          name: :mermaid, translatable: false, audit: :digest, cast: TYPED_TEXT,
          options: lambda { |options, _earlier|
            raise ArgumentError, "a mermaid field names its drawing field, `drawing:`" unless options[:drawing].is_a?(Symbol) || options[:drawing].is_a?(String)
            raise ArgumentError, "`max:` on a mermaid field is a number of characters, a positive Integer" if options.key?(:max) && !(options[:max].is_a?(Integer) && options[:max].positive?)
            raise ArgumentError, DESCRIPTION_REFUSAL if options.key?(:description) && !(options[:description].is_a?(Symbol) || options[:description].is_a?(String))
            refuse_choice_and_string_options(options.except(:drawing, :description))
          },
          finish: lambda { |field, fields|
            drawing = fields.find { |candidate| candidate.name == field.options[:drawing].to_s }
            unless drawing&.type == :diagram_drawing && drawing.translated? == field.translated?
              raise ArgumentError, "the mermaid field #{field.name} names `drawing: #{field.options[:drawing].inspect}`, which is to be a diagram_drawing field of this definition, translated as the source is"
            end
            next unless field.options.key?(:description)

            description = fields.find { |candidate| candidate.name == field.options[:description].to_s }
            unless %i[string text].include?(description&.type) && description.translated? == field.translated?
              raise ArgumentError, "the mermaid field #{field.name} names `description: #{field.options[:description].inspect}`, which is to be a string or text field of this definition, translated as the source is"
            end
          },
          validate: lambda { |field:, value:, raw:, errors:, stored:, translations:|
            texts = [ value ]
            texts += translations.values.map { |values| TYPED_TEXT.call(values.to_h[field.name]) } if field.translated?
            texts.compact.uniq.each { |text| refuse_long_mermaid(field, text, errors) }
          }
        )
      end

      # The drawing of a Diagram block (spec §1 and §3): `{ "svg", "from" }`,
      # sent by the editor's script as JSON, read back from jsonb as a Hash.
      # The cast cleans the SVG (`Diagrams::Drawing.clean`, the security
      # boundary) and keeps `from`, the digest of the source the frame drew,
      # as it was given when it is a digest (`DRAWING_FROM`): it cannot see
      # the source. A value that is no such pair, holds another `from` or
      # does not clean casts to the `DRAWING_REFUSED` mark, and only
      # a mark this save was handed is refused (`raw`, and every language of
      # `translations`): a stored drawing that today's rules refuse reads back
      # as the mark (no drawing) and stops no save. Translated with its
      # source, never offered to an AI provider, audited as a digest, and
      # not tracked for translation state: it is derived from the source,
      # whose change is what makes a translation outdated.
      def diagram_drawing
        FieldType.new(
          name: :diagram_drawing, translatable: false, audit: :digest, tracked: false,
          cast: ->(value) { cast_drawing(value) },
          options: ->(options, _earlier) { refuse_choice_and_string_options(options) },
          validate: lambda { |field:, value:, raw:, errors:, stored:, translations:|
            sent = [ raw ]
            sent += translations.values.map { |values| values.to_h[field.name] } if field.translated?
            errors.add(field.name, :invalid_drawing) if sent.any? { |candidate| candidate.is_a?(Hash) && candidate.key?(DRAWING_REFUSED) }
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

      # One error per refusal of `Diagrams::Source`, said once however many
      # languages share it. The limit is the smaller of `max:` and the
      # source's own, in the Code field's sentence.
      def refuse_long_mermaid(field, text, errors)
        limit = [ field.options[:max], Diagrams::Source::MAX_CHARACTERS ].compact.min
        return unless text.length > limit

        add_once(errors, field.name, :too_long, count: limit, message: :code_too_long, limit: ActiveSupport::NumberHelper.number_to_delimited(limit))
      end

      def add_once(errors, name, type, **options)
        errors.add(name, type, **options) unless errors.added?(name, type, **options)
      end

      def cast_drawing(value)
        pair = value.is_a?(String) ? parse_json(value) : value
        pair = pair.to_h.stringify_keys if pair.is_a?(Hash)
        return pair.slice(DRAWING_REFUSED) if pair.is_a?(Hash) && pair.key?(DRAWING_REFUSED)
        return { DRAWING_REFUSED => "shape" } unless pair.is_a?(Hash) && pair["svg"].is_a?(String) && pair["from"].is_a?(String) && pair["from"].match?(DRAWING_FROM)

        result = Diagrams::Drawing.clean(pair["svg"])
        result.svg ? { "svg" => result.svg, "from" => pair["from"] } : { DRAWING_REFUSED => result.reason.to_s }
      end

      def parse_json(text)
        JSON.parse(text)
      rescue JSON::ParserError
        nil
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

      HELP_REFUSAL = "`help:` is a line under a string or a text field, written as a String".freeze

      def check_help(options)
        raise ArgumentError, HELP_REFUSAL if options.key?(:help) && !(options[:help].is_a?(String) && options[:help].strip != "")
      end

      def refuse_string_options(options)
        raise ArgumentError, HELP_REFUSAL if options.key?(:help)
        raise ArgumentError, "`placeholder_from:` is for a string field and names a select field declared before it" if options.key?(:placeholder_from)
        raise ArgumentError, "`format:` is for a string field" if options.key?(:format) || options.key?(:format_message)
        raise ArgumentError, "`drawing:` is a mermaid field's, naming its diagram_drawing field" if options.key?(:drawing)
        raise ArgumentError, DESCRIPTION_REFUSAL if options.key?(:description)
      end

      DESCRIPTION_REFUSAL = "`description:` is a mermaid field's, naming the text field that describes its drawing".freeze

      def url?(value)
        URL_SCHEMES.include?(URI.parse(value).scheme.to_s.downcase)
      rescue URI::Error
        false
      end
    end
  end
end
