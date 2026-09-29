# The per-locale rich-text body (design spec §3.1) `Post` and `ContentBlock`
# share: one Tiptap/ProseMirror JSON document per language in the jsonb
# `body` column (`{ locale => tiptap_doc }`), read back as a
# `RichText::Document` and validated against `RichText::Schema` before it's
# ever written.
#
# Everything outside the models reads and writes through
# `#body_document`/`#assign_body` (and `Locales.read(record, :body)` for
# public output) rather than the raw Mobility accessor: those are where a
# stored value becomes a `RichText::Document`, and where a submitted JSON
# String is parsed and a "nothing" write is refused.
module HasRichTextBody
  extend ActiveSupport::Concern

  included do
    # The default jsonb backend (config/initializers/mobility.rb), same as
    # every other translated column. A stored value is a whole document
    # Hash, not a String -- Mobility's jsonb backend stores whatever JSON
    # value it's handed per locale, and its `presence` plugin only ever
    # nils out `""`.
    translates :body

    validate :body_documents_valid
  end

  # This locale's document, read literally -- no fallback, the same rule
  # every admin/MCP reader follows (`Locales.read` is the fallback-aware
  # reader for public output). A locale never written, or holding something
  # that isn't a document Hash at all, reads as `RichText::Document.empty`
  # rather than nil, so callers never have to special-case "no document".
  def body_document(locale:)
    value = body(locale: locale.to_s)
    value.is_a?(Hash) ? RichText::Document.new(value) : RichText::Document.empty
  end

  # Writes `document` as this locale's body (marks in canonical order,
  # `#normalize`), leaving every other locale's alone. Accepts what the write path actually receives: a document Hash
  # (MCP after Markdown conversion, seeds), a `RichText::Document`, or the
  # JSON String the admin's hidden input submits (design spec §4.1).
  #
  # A String that isn't valid JSON is stored *as that String* rather than
  # raising or being silently dropped: `#body_documents_valid` then rejects
  # it like any other malformed document, so a broken submission comes back
  # as an ordinary validation error on `body` (a 422 in the admin) and is
  # never persisted -- the same "report, don't crash" posture
  # `RichText::Document#validate` takes toward malformed shapes.
  #
  # Nothing -- `nil`, `""`, or JSON that parses to nothing (`"null"`) --
  # is rejected the same way (fix round 1, m3), not treated as "clear this
  # locale": writing nil through Mobility would silently delete the
  # locale's document. Clearing a body is an explicit empty document
  # (`{"type":"doc","content":[]}`, or the empty paragraph an editor
  # sends), which is stored like any other and reads back as blank. The
  # rejected locale is remembered in `@unassignable_body_locales` (nothing
  # is written for it) so `#body_documents_valid` can report it.
  def assign_body(document, locale:)
    code = locale.to_s
    value =
      case document
      when RichText::Document then document.normalized.to_h
      when String then normalize(parse_body_json(document))
      else normalize(document)
      end

    unassignable_body_locales.delete(code)
    return unassignable_body_locales << code if value.nil?

    public_send(:body=, value, locale: code)
  end

  private

  def unassignable_body_locales = (@unassignable_body_locales ||= Set.new)

  # A document Hash is stored with its marks in `RichText::Schema`'s
  # canonical order (`RichText::Document#normalized`; Task 7 fix round 1)
  # -- Tiptap orders marks by its own extension priority, which isn't the
  # schema's, and a reorder alone must neither read as an edit to
  # `#body_documents_valid`'s "did this locale change" check nor make the
  # same content digest differently. Anything that isn't a Hash (a
  # malformed String, nil) passes through for validation to reject.
  def normalize(value) = value.is_a?(Hash) ? RichText::Document.new(value).normalized.to_h : value

  # A blank String is "nothing", not an unparseable document: stored raw,
  # Mobility's `presence` plugin would turn `""` into nil and delete the
  # locale anyway.
  def parse_body_json(string)
    return nil if string.strip.empty?

    JSON.parse(string)
  rescue JSON::ParserError
    string
  end

  # Only the locales whose document changed in this save are validated
  # (every locale, for a new record) -- not every stored locale on every
  # save. A document that validated when it was written can go stale later
  # through no edit of its own (an internal link's target page deleted, an
  # image's `Media::Asset` removed); re-validating it on every unrelated save
  # would make a post whose English body links to a since-deleted page
  # impossible to retitle, or to edit in German. Stale references are the
  # renderer's job to degrade (spec §7: "renders nothing or plain text"),
  # not something an unrelated edit should be blocked on.
  #
  # Errors land on `:body` (spec §3.5), the name the admin's error slot and
  # every caller already know.
  def body_documents_valid
    unassignable_body_locales.each { |code| errors.add(:body, :invalid, message: "(#{code}) isn't a document -- send an empty document to clear it") }

    previous = persisted? ? attribute_in_database(:body).to_h : {}

    read_attribute(:body).to_h.each do |code, value|
      next if previous[code] == value
      # `assign_body` stores `#normalized` documents, so a body stored before
      # a normalisation rule existed comes back "changed" on every autosave
      # of an unrelated field (the editor always resends it). A difference
      # that is only normalisation isn't an edit: without this, a legacy
      # body that breaks a newer structural rule would wedge every save of
      # the record while the editor shows it read-only.
      next if previous[code].is_a?(Hash) && RichText::Document.new(previous[code]).normalized.to_h == value

      body_errors_for(value, previous[code]).each { |message| errors.add(:body, :invalid, message: "(#{code}) #{message}") }
    end
  end

  # The same reasoning one level down, *within* a changed document (Task 7
  # fix round 1, I2): an edit to a body that already held a dead reference
  # (a link to a since-deleted page, an image whose `Media::Asset` is gone)
  # must still save -- the editor sends the whole document back, dead
  # reference included, on every keystroke. So existence checks only
  # apply to references that are new relative to this locale's stored
  # document (`RichText::Document#validate(known_references:)`); linking
  # to a missing record *now* is still an error.
  def body_errors_for(value, previous)
    return [ "isn't a valid document" ] unless value.is_a?(Hash)

    known = previous.is_a?(Hash) ? RichText::Document.new(previous).references : nil
    RichText::Document.new(value).validate(known_references: known)
  end
end
