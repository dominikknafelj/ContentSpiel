module Admin
  module TrashScreen
    # The Trash screen's type tabs: All, Pages, Posts, Images and Forms, each
    # with how many rows it lists, drawn as the shared segmented control's
    # links (`Admin::Ui::SegmentedComponent`). Plain links (`?type=pages|posts|
    # images|forms`, none for All): a tab change is a navigation, so the page
    # number is dropped with it. The counts are `Admin::TrashController.counts`
    # (what the viewer may act on, branch roots for pages), the same numbers
    # the sidebar's badge sums, handed in by the screen.
    class TabsComponent < Admin::AdminComponent
      # A tab's word key, its `?type=` value and the model key it counts.
      TABS = [
        [ "all", nil, nil ],
        [ "pages", "pages", "page" ],
        [ "posts", "posts", "post" ],
        [ "images", "images", "media" ],
        [ "forms", "forms", "form" ]
      ].freeze

      # `counts` is `{ "page" => n, "post" => n, "media" => n }`; `current` the
      # tab key ("pages", ...) or nil for All; `url` turns a tab key (or nil)
      # into its path.
      def initialize(counts:, current:, url:)
        @counts = counts
        @current = current
        @url = url
      end

      # A kind's tab is drawn only when `counts` holds it: the Forms tab is
      # handed in for a holder of `forms.manage` alone (forms are a module
      # of their own, and nobody else may restore one).
      def tabs
        TABS.select { |_, _, model| model.nil? || @counts.key?(model) }.map do |word, key, model|
          { label: t(".#{word}"), count: model ? @counts.fetch(model, 0) : @counts.values.sum, current: key == @current, href: @url.call(key) }
        end
      end
    end
  end
end
