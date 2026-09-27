module Admin
  module Columns
    # The Trix editor for a `has_rich_text` column (`Page`/`Post#body`, spec
    # §4.3) -- `rich_text_area_tag` (an `ActionText::TagHelper` alias for
    # `rich_textarea_tag`, available here via `helpers` since it's mixed
    # into every `ActionController::Base`, not `ActionView::Helpers`
    # directly) renders the hidden field Trix writes to plus the
    # `<trix-editor>` custom element itself.
    class RichTextColumnComponent < Base
      # `original` here is a rendered rich text body -- an
      # `ActionText::RichText#body` (or anything else that responds to
      # `to_s` with HTML, e.g. a plain string in a test/preview) -- from the
      # *other* locale's own `has_rich_text`. Re-wrapping it in
      # `ActionText::Content` and calling `to_s` on that (not the value's
      # own `to_s`) is what actually sanitizes it: `ActionText::Content#to_s`
      # renders through Trix's own attachment/sanitization pipeline, so a
      # translated body carrying, say, a stray `onclick` from a bad paste
      # never reaches this read-only column unescaped.
      def sanitized_original = ActionText::Content.new(original.to_s).to_s
    end
  end
end
