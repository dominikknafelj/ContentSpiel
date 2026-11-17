module Admin
  module Ui
    # What changed between two sides of a page: by name, as the publish,
    # restore and Publish now dialogs show it, and with each entry's words,
    # as the History screen's comparison does. Both sides are built in
    # memory, in the form a copy stores them, so the preview needs no row.
    class ChangesOverviewComponentPreview < ViewComponent::Preview
      # A copy's side as `Publishing::Changes` reads one, with no id: it is no
      # row (`Publishing::Snapshot.blocks_from` names a block's copy by it).
      Side = Data.define(:snapshot, :blocks, :live_at) do
        def id = nil
      end

      def names = render(overview(:names))

      def diffs = render(overview(:diffs))

      def none
        side = was
        render Admin::Ui::ChangesOverviewComponent.new(record: page, changes: ::Publishing::Changes.between(page, from: side, to: side),
          holds: nil, locale: "en", detail: :diffs)
      end

      private

      def overview(detail)
        Admin::Ui::ChangesOverviewComponent.new(record: page, changes: ::Publishing::Changes.between(page, from: was, to: now), holds: nil, locale: "en", detail: detail)
      end

      def page = @page ||= Page.new(id: 0)

      def was
        Side.new(snapshot: { "fields" => { "title" => { "en" => "Pricing" }, "subtitle" => { "en" => "Plans for every team" } } },
          blocks: [ block(1, "Welcome to our plans."), block(2, "Every plan has a free month."), block(3, "Write to us with questions.") ],
          live_at: 3.days.ago)
      end

      def now
        Side.new(snapshot: { "fields" => { "title" => { "en" => "Pricing and plans" }, "subtitle" => { "en" => "Plans for every team" } } },
          blocks: [ block(3, "Write to us with questions."), block(1, "Welcome to our new plans."), block(2, "Every plan has a **free month**."),
                    block(4, "Ask for a quote.") ],
          live_at: nil)
      end

      def block(id, markdown)
        body = RichText::Document.from_markdown(markdown).first.to_h
        { "id" => id, "block_type" => "rich_text", "body" => { "en" => body }, "section_id" => nil, "section_column" => nil }
      end
    end
  end
end
