module Admin
  module Ui
    # The "nothing here yet" placeholder for any admin list or panel that can
    # be empty -- no blocks on a page, no posts of a type, no tags (spec
    # §4.3/§5). `description:` is optional (a title alone is often enough);
    # `action` is a slot, not a `label:`/`url:` pair, because the action is
    # usually a full `Ui::ButtonComponent` wired to a specific Stimulus action or
    # route the caller already has in hand (e.g. "+ Add block" opens the block
    # picker; "New post" asks for a content type first) -- this component has
    # no business constructing that itself.
    #
    # It draws no border of its own (design pass spec §4): it sits *inside* the
    # card a list's rows would be in, so an empty list and a full one are the
    # same card. At most one action -- a second would be a choice the list
    # itself should offer.
    class EmptyStateComponent < AdminComponent
      renders_one :action

      def initialize(title:, description: nil)
        @title = title
        @description = description
      end

      private

      attr_reader :title, :description
    end
  end
end
