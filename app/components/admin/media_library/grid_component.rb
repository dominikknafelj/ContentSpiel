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
    class GridComponent < Admin::AdminComponent
      def initialize(assets:, url_options: {})
        @assets = assets
        @url_options = url_options
      end

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

      private

      attr_reader :assets, :url_options
    end
  end
end
