module Admin
  module TrashScreen
    # The Trash screen's type tabs (design pass round 3, handoff §4.9): All,
    # Pages, Posts and Images, each with how many rows it lists, drawn as the
    # segmented control the posts list uses. Plain links (`?type=pages|posts|
    # images`, none for All) -- a tab change is a navigation, so the page
    # number is dropped with it. The counts are `Admin::TrashController.counts`
    # (what the viewer may act on, branch roots for pages), the same numbers
    # the sidebar's badge sums, handed in by the screen.
    class TabsComponent < Admin::AdminComponent
      TABS = [
        [ "All", nil, nil ],
        [ "Pages", "pages", "page" ],
        [ "Posts", "posts", "post" ],
        [ "Images", "images", "media" ]
      ].freeze

      LINK_CLASS = "inline-flex items-center gap-1.5 border-r border-line px-3 py-1.5 text-sm last:border-r-0".freeze

      # `counts` is `{ "page" => n, "post" => n, "media" => n }`; `current` the
      # tab key ("pages", ...) or nil for All; `url` turns a tab key (or nil)
      # into its path.
      def initialize(counts:, current:, url:)
        @counts = counts
        @current = current
        @url = url
      end

      def tabs
        TABS.map do |label, key, model|
          { label:, key:, count: model ? @counts.fetch(model, 0) : @counts.values.sum, current: key == @current, href: @url.call(key) }
        end
      end

      def link_class(current)
        "#{LINK_CLASS} #{current ? "bg-sunken font-semibold text-ink" : "text-meta hover:bg-sunken"}"
      end
    end
  end
end
