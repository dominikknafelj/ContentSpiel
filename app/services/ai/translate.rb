module AI
  # Asks the configured AI provider to translate some of a record's fields
  # from the primary language into `to` (translation helpers spec §6.3), and
  # hands the answers back as *suggestions* -- `#suggestions`
  # (`{ field => String | RichText::Document }`) and `#warnings`
  # (`{ field => [String] }`, a rich-text body's Markdown repairs). Nothing
  # is saved, ever: the editor's **Use** fills the input, and only that
  # input's ordinary autosave writes (Review Focus 4) -- which is also what
  # records a fresh translation digest for it (§3.2). This service never
  # calls `save`, `update` or `update_columns` on the record.
  #
  # The record is anything `Translations::EditRight` knows: a Page, Post,
  # ContentBlock, Media::Asset or the SiteSetting row.
  #
  # Rights: `ai.translate`, plus exactly the record's edit right -- asking
  # for a suggestion is never allowed where typing the text in yourself
  # wouldn't be.
  #
  # One request per text format, so at most two: plain values go as they
  # are (`format: :plain`), rich-text bodies as `RichText::Document
  # #to_markdown` (`format: :markdown`) and come back through
  # `RichText::Document.from_markdown`, the same round trip MCP uses (images
  # as `::image{…}` directives, internal links as `cs:page/42`).
  class Translate < ApplicationService
    include Translations::EditRight

    # The per-request cap (spec §10, narrower than the spec's original
    # 30,000 characters): one request must finish inside the provider's
    # 25 s timeout with no retry (`AI::Providers::Anthropic::TIMEOUT`,
    # itself bounded by the production proxy's response timeout and Puma's
    # thread count -- see its comment), and 6,000 characters is what
    # reliably does. Counted over what's actually sent -- blank originals
    # skipped, rich text as its Markdown. Public: the bulk "Translate empty
    # fields" (Task 8) splits its request by these, so a split never trips
    # them.
    MAX_FIELDS = 20
    MAX_CHARACTERS = 6_000

    TOO_MUCH = "Too much at once — translate in parts".freeze

    attr_reader :suggestions, :warnings

    def initialize(record, fields:, to:, actor: Current.actor)
      @record = record
      @fields = Array(fields).map(&:to_s).uniq
      @to = to.to_s
      @actor = actor
      @suggestions = {}
      @warnings = {}
    end

    def call
      return denied("ai.translate", nil) unless authorize!("ai.translate", nil)

      refused = edit_refusal(@record) { |key| authorize!(key, @record) }
      return denied(refused, @record) if refused
      return failure(@record, [ AI::NOT_CONFIGURED ]) unless AI.configured?
      return failure(@record, [ "Choose a language to translate into" ]) unless Translations.target_locales.include?(@to)

      untranslatable = @fields - @record.class.translation_tracked_fields(@record)
      # Named by label, the way the editor shows the field, never by attribute.
      return failure(@record, [ "#{untranslatable.map(&:humanize).to_sentence} can't be translated" ]) if untranslatable.any?

      originals = read_originals
      return failure(@record, [ TOO_MUCH ]) if originals.size > MAX_FIELDS || characters(originals) > MAX_CHARACTERS
      return success(@record) if originals.empty? # nothing to ask, so nothing asked -- and nothing to log

      provider = AI.provider
      originals.group_by { |_, original| original[:format] }.each do |text_format, group|
        translations = provider.translate(texts: group.map { |_, original| original[:text] }, from: from, to: @to, format: text_format)
        # The built-in provider checks this itself; a plugin's might not,
        # and a short answer would otherwise hand one field another's text.
        raise AI::Error, "The AI provider's answer didn't match the request. Try again." unless translations.size == group.size

        group.zip(translations).each { |(field, original), translation| suggest(field, original, translation) }
      end

      # No snapshot: the event must carry no text, and a snapshot of the
      # subject is a full copy of its content (global constraints).
      record_event("ai.translated", subject: @record, snapshot: nil, metadata: {
        "fields" => originals.map(&:first), "from" => from, "to" => @to,
        "provider" => Current.site.ai_provider, "model" => AI.model, "characters" => characters(originals)
      })
      success(@record)
    rescue AI::Error => e
      # Whatever was collected before a second call failed is dropped: a
      # failure hands back no suggestions at all, and records no event.
      @suggestions = {}
      @warnings = {}
      failure(@record, [ e.message ])
    end

    private

    def from = Translations.primary_locale

    # `[[field, { text:, format:, document: }], ...]`, in the order asked,
    # without the fields whose original is blank (there's nothing to
    # translate) -- or isn't text at all: a translated schema group field
    # reads as its raw Hash/Array, which no provider can be handed, so the
    # bulk request (which asks for every missing field) skips it rather
    # than failing for everything else.
    def read_originals
      @fields.filter_map do |field|
        value = @record.translation_value(field, from)
        next if value.blank?

        case value
        when RichText::Document then [ field, { text: value.to_markdown, format: :markdown, document: value } ]
        when String then [ field, { text: value, format: :plain } ]
        end
      end
    end

    def characters(originals) = originals.sum { |_, original| original[:text].length }

    # A rich-text suggestion is parsed knowing the original's references,
    # so a link or image the original already had is kept even when the
    # actor couldn't add it afresh (`RichText::Document.from_markdown`'s
    # `known_references`, the same rule as editing that document) --
    # parsed as the actor, whose read rights decide the rest.
    def suggest(field, original, translation)
      if original[:format] == :markdown
        document, warnings = as_actor { RichText::Document.from_markdown(translation, known_references: original[:document].references) }
        @suggestions[field] = document
        @warnings[field] = warnings
      else
        @suggestions[field] = translation
        @warnings[field] = []
      end
    end
  end
end
