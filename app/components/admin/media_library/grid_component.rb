module Admin
  # `MediaLibrary`, not `Media`: a real `Admin::Media` module would shadow
  # the top-level `Media` module (`app/models/media/*`,
  # `app/services/media/*`) for every *bare* `Media::` reference lexically
  # nested under `module Admin` elsewhere in this app -- Ruby's constant
  # lookup checks a class's own lexical scope, `Admin` included, before it
  # ever falls back to the top level. That trap briefly existed mid-task
  # (see the git history) and broke the hero-image and image-block upload
  # paths (`NameError: uninitialized constant Admin::Media::Upload`)
  # without touching a single line of this module's own code -- named
  # `MediaLibrary` instead, so `Admin.const_defined?(:Media, false)` never
  # becomes true and no other `Admin::*` file ever has to remember to
  # write `::Media::` on its own account. `test/lib/admin_media_namespace_
  # test.rb` guards against this regressing.
  module MediaLibrary
    # The Media module's own grid (media library design spec §6): one
    # thumbnail card per asset, each linking to its own detail panel
    # (`Admin::MediaController#show`). Every asset this renders must be
    # loaded through `Media::Asset.with_variants` (`Admin::MediaController
    # #filtered_assets`) -- `#thumbnail_url` reads `#srcset`, which is
    # exactly the N+1 that scope exists to prevent over a whole page of
    # cards.
    #
    # `pick: true` is the same grid inside `Media::PickerComponent`'s
    # Library tab (Task 8, `Admin::MediaController#index` with `picker=1`):
    # each card is then a button that hands the asset back to the picker
    # (`admin--media-picker#pick`) instead of a link to the detail panel --
    # one grid, one search/pagination endpoint, two ways of acting on a
    # card. `locale` is the editing language the picked asset's default
    # alt/caption are read in (`#pick_payload`), which the fields the
    # picker fills show as their placeholders.
    class GridComponent < Admin::AdminComponent
      def initialize(assets:, url_options: {}, pick: false, locale: ::Locales.default)
        @assets = assets
        @url_options = url_options
        @pick = pick
        @locale = locale
      end

      def pick? = @pick

      # The thumbnail ruling (design spec §6): the `w480` variant once
      # it's processed, else the original -- `#srcset` already only ever
      # lists a variant that's finished (`Media::Asset#srcset`'s own
      # comment), so "processed" here just means "present in the list this
      # returns", not a second check of its own.
      def thumbnail_url(asset)
        entry = asset.srcset.find { |_path, width| width == 480 }
        entry ? entry.first : asset.src
      end

      def show_path(asset) = helpers.admin_medium_path(asset, **url_options)

      # What `admin--media-picker#pick` dispatches as `media-picker:picked`'s
      # detail, as one JSON action param (not one param per key: Stimulus
      # JSON-parses each param value on its own, so an alt text that happens
      # to read "42" or "true" would arrive as a number or a boolean). `url`
      # is the thumbnail -- only ever used to *show* the choice in CS
      # Studio; what gets saved is `id`. `alt`/`caption` are the asset's
      # own defaults in the editing language, resolved the same way the
      # public page would (`Media::Asset#alt_text` with no override), so a
      # blank per-use override field can show what will actually be used.
      def pick_payload(asset)
        {
          id: asset.id,
          url: thumbnail_url(asset),
          title: asset.title,
          alt: asset.alt_text(override: nil, locale: locale),
          caption: asset.caption_text(override: nil, locale: locale).to_s
        }.to_json
      end

      private

      attr_reader :assets, :url_options, :locale
    end
  end
end
