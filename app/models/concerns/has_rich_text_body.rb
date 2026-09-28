# The per-locale rich-text body (design spec §3.1) `Post` and `ContentBlock`
# share: one Tiptap/ProseMirror JSON document per language in the jsonb
# `body_doc` column (`{ locale => tiptap_doc }`), read back as a
# `RichText::Document` and validated against `RichText::Schema` before it's
# ever written.
#
# `body_doc` is the column's interim name -- the ActionText `body` it
# replaces stays declared (`translates :body, backend: :action_text`) on
# both models until Task 6 has migrated every ActionText row and dropped
# ActionText, then renames `body_doc` to `body`. Everything outside the
# models reads and writes through `#body_document`/`#assign_body` (and
# `Locales.read(record, :body)` for public output), never `body_doc`
# directly, so that rename touches this file and the migration only.
module HasRichTextBody
  extend ActiveSupport::Concern

  included do
    # The default jsonb backend (config/initializers/mobility.rb), same as
    # every other translated column. A stored value is a whole document
    # Hash, not a String -- Mobility's jsonb backend stores whatever JSON
    # value it's handed per locale, and its `presence` plugin only ever
    # nils out `""`.
    translates :body_doc

    validate :body_documents_valid
  end

  # This locale's document, read literally -- no fallback, the same rule
  # every admin/MCP reader follows (`Locales.read` is the fallback-aware
  # reader for public output). A locale never written, or holding something
  # that isn't a document Hash at all, reads as `RichText::Document.empty`
  # rather than nil, so callers never have to special-case "no document".
  def body_document(locale:)
    value = body_doc(locale: locale.to_s)
    value.is_a?(Hash) ? RichText::Document.new(value) : RichText::Document.empty
  end

  # Writes `document` as this locale's body, leaving every other locale's
  # alone. Accepts what the write path actually receives: a document Hash
  # (MCP after Markdown conversion, seeds), a `RichText::Document`, or the
  # JSON String the admin's hidden input submits (design spec §4.1).
  #
  # A String that isn't valid JSON is stored *as that String* rather than
  # raising or being silently dropped: `#body_documents_valid` then rejects
  # it like any other malformed document, so a broken submission comes back
  # as an ordinary validation error on `body` (a 422 in the admin) and is
  # never persisted -- the same "report, don't crash" posture
  # `RichText::Document#validate` takes toward malformed shapes.
  def assign_body(document, locale:)
    value =
      case document
      when RichText::Document then document.to_h
      when String then parse_body_json(document)
      else document
      end

    public_send(:body_doc=, value, locale: locale.to_s)
  end

  private

  def parse_body_json(string)
    return nil if string.blank?

    JSON.parse(string)
  rescue JSON::ParserError
    string
  end

  # Only the locales whose document changed in this save are validated
  # (every locale, for a new record) -- not every stored locale on every
  # save. A document that validated when it was written can go stale later
  # through no edit of its own (an internal link's target page deleted, an
  # image's `MediaAsset` removed); re-validating it on every unrelated save
  # would make a post whose English body links to a since-deleted page
  # impossible to retitle, or to edit in German. Stale references are the
  # renderer's job to degrade (spec §7: "renders nothing or plain text"),
  # not something an unrelated edit should be blocked on.
  #
  # Errors land on `:body` (spec §3.5), the name the admin's error slot and
  # every caller already know -- not `body_doc`, the column's interim name.
  def body_documents_valid
    previous = persisted? ? attribute_in_database(:body_doc).to_h : {}

    read_attribute(:body_doc).to_h.each do |code, value|
      next if previous[code] == value

      body_errors_for(value).each { |message| errors.add(:body, :invalid, message: "(#{code}) #{message}") }
    end
  end

  def body_errors_for(value)
    return [ "isn't a valid document" ] unless value.is_a?(Hash)

    RichText::Document.new(value).validate
  end
end
