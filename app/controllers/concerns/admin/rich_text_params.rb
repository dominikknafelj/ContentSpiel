module Admin
  # Reads a rich-text body out of an autosave PATCH (tiptap spec §4.1) for
  # `Admin::PostsController` and `Admin::ContentBlocksController` alike.
  #
  # Two params can carry it:
  # - `body` -- the hidden input's document JSON String, the permanent
  #   contract (Tiptap writes `editor.getJSON()` there from Task 7 on).
  #   Passed through untouched: `Posts::Save`/`ContentBlocks::Save` hand it
  #   to `assign_body`, which parses it, and the model's validation rejects
  #   anything that isn't a valid document (a 422, nothing persisted).
  # - `body_markdown` -- the interim Markdown textarea
  #   (`Admin::Columns::RichTextColumnComponent`, Task 5 until Task 7).
  #   Converted here with `RichText::Document.from_markdown`, and whenever
  #   it's present it wins over `body` outright: `body` is dropped from the
  #   save. The hidden input is never refreshed by an autosave response,
  #   so after the first Markdown edit it holds a stale document -- letting
  #   it win on any later save would silently revert that edit.
  #
  #   Markdown is only converted when it actually differs from the
  #   Markdown the stored document renders to. Every autosave resends the
  #   whole form, so an edit to the *title* also resends the untouched
  #   textarea; converting that back would round-trip the stored document
  #   through Markdown on every unrelated save, which isn't lossless for
  #   everything a document can hold (empty spacer paragraphs don't survive
  #   Markdown, ledger ruling m9). Unchanged Markdown therefore leaves the
  #   stored body exactly as it is.
  #
  # The returned warnings are what `from_markdown` couldn't represent
  # exactly (an unknown directive kept as text, a `cs:` link to a missing
  # record) -- nil when no Markdown was converted, so the caller knows
  # whether to touch the field's warnings slot at all.
  module RichTextParams
    extend ActiveSupport::Concern

    private

    # Mutates `translated` (the String-keyed translated-column Hash the
    # controller hands its service) in place and returns the warnings.
    def apply_body_markdown(translated, source_params, record)
      return nil unless source_params.key?(:body_markdown)

      translated.delete("body")
      markdown = normalize_markdown(source_params[:body_markdown])
      stored = Admin::Columns::RichTextColumnComponent.markdown_for(record.body_document(locale: admin_locale))
      return [] if markdown == normalize_markdown(stored)

      document, warnings = RichText::Document.from_markdown(markdown)
      translated["body"] = document.to_h
      warnings
    end

    # A `<textarea>` submits CRLF line endings (HTML's form-encoding rule)
    # and may gain or lose trailing whitespace; neither is a real edit.
    def normalize_markdown(markdown) = markdown.to_s.gsub("\r\n", "\n").rstrip

    def body_warnings_stream(column_id, warnings)
      id = Admin::Columns::RichTextColumnComponent.warnings_id(column_id)
      turbo_stream.replace(id, partial: "admin/shared/field_warnings", locals: { id: id, messages: warnings })
    end
  end
end
