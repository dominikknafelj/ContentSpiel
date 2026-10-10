module Admin
  module Columns
    # A library image field (media library design spec §6, Task 8): a
    # page's hero (`hero_media_asset_id`) and an image block's image
    # (`media_asset_id`). Shows the chosen image's thumbnail and title,
    # **Choose image**/**Change image** (opens `Media::PickerComponent`)
    # and **Remove image**, around one hidden input named `html_name` that
    # holds the asset id -- the one thing that's saved.
    #
    # `admin--media--field` writes the picked id (or "" on Remove) into that
    # input and dispatches a bubbling `input`, so the enclosing form's own
    # `admin--saving--autosave` sends it with everything else -- the same contract
    # the rich-text column's hidden input has. "" is a deliberate clear
    # (`Media::Choosing`: clearing needs only the edit right); resending the
    # stored id is a no-op; a different id needs `media.upload` and an
    # existing asset, refused into this column's own error slot
    # (`#{id}-errors`, the key the save service reports under -- `hero_image`
    # / `image` -- so `id` must be `"<prefix>-hero_image"`/`"<prefix>-image"`).
    #
    # Choose is only offered with `media.upload` (the picker isn't even on
    # the page without it); Remove needs nothing more than the form being
    # editable, which the form's own `<fieldset disabled>` already decides
    # for every button here.
    #
    # `placeholder_ids:` names the per-use override fields beside this one
    # (`{ alt: "page-hero_alt" }`, `{ alt: ..., caption: ... }`) -- after a
    # pick their placeholders become the new image's own defaults, and
    # after Remove they're emptied, so the placeholder always shows what a
    # blank override would fall back to. Their server-rendered placeholders
    # are the caller's job (`#default_alt`/`#default_caption` below); the
    # controller also re-applies them on connect (`#defaults`).
    #
    # A refused choice (a forged or since-deleted id, no `media.upload`)
    # is answered by re-rendering this whole component with the *stored*
    # image and the refusal in its error slot (`Admin::MediaFields
    # #refused_media_field_stream`) -- the client had already swapped the
    # thumbnail, title and button over to the refused pick, and left alone
    # the hidden input would resend the refused id on every later
    # autosave.
    #
    # `value` is the chosen `Media::Asset` or nil. Load it through
    # `Media::Asset.with_variants` when several of these are rendered at
    # once (the page editor's block cards) -- `#thumbnail_url` reads
    # `#srcset`.
    class MediaColumnComponent < Base
      def initialize(section_id:, placeholder_ids: {}, **options)
        super(**options)
        @section_id = section_id
        @placeholder_ids = placeholder_ids
      end

      def asset = value

      # The wrapper's id -- what a stream replacing this whole field targets.
      def section_dom_id = section_id

      def chosen? = asset.present?

      def can_choose? = can?("media.upload")

      def label_id = "#{id}-label"

      # The same thumbnail rule as the Media module's own grid
      # (`Media::Asset#thumbnail_url`).
      def thumbnail_url = asset&.thumbnail_url

      def choose_label = chosen? ? "Change image" : "Choose image"

      def root_data
        {
          field_name: name,
          controller: "admin--media--field",
          action: "media-picker:picked->admin--media--field#picked",
          "admin--media--field-placeholder-ids-value": placeholder_ids.to_json,
          "admin--media--field-defaults-value": defaults.to_json
        }
      end

      # The rendered image's own alt/caption defaults, which
      # `admin--media--field` writes into the override fields' placeholders
      # on connect -- so when this component is re-rendered by a stream
      # after a refused choice (`Admin::PagesController#update`,
      # `Admin::ContentBlocksController#update`), the placeholders the
      # client had already switched to the refused image's go back to the
      # stored one's too, without the stream having to know which override
      # fields sit beside this one.
      def defaults = { alt: self.class.default_alt(asset, editing_locale), caption: self.class.default_caption(asset, editing_locale) }

      # nil only for a caller that passes none (a Lookbook preview), which
      # edits the primary language.
      def editing_locale = locale.presence || ::Locales.default

      # The chosen image's own defaults in `locale` (`Media::Asset
      # #alt_text`/`#caption_text` with no override -- what the public page
      # shows when the override is blank), for callers rendering the
      # override fields' initial placeholders.
      def self.default_alt(asset, locale) = asset&.alt_text(override: nil, locale: locale).to_s

      def self.default_caption(asset, locale) = asset&.caption_text(override: nil, locale: locale).to_s

      private

      attr_reader :section_id, :placeholder_ids
    end
  end
end
