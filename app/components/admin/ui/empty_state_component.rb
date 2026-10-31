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
    # It follows the brand book's empty-state rule: "Empty states are one dim
    # line plus an action, left-aligned where the first row would be. Don't
    # centre them and don't add a second line in another style." So the title
    # and the description are ONE paragraph in `text-dim`, the title first
    # and the description after it in the same style, and each caller writes
    # its two parts as a sentence pair ("No posts yet. Choose a content type
    # to create your first post."): the component joins them with a space and
    # adds no punctuation, which is the caller's language's to write. The
    # action follows on its own line, left-aligned under the text. The
    # padding is the dashboard card's empty line (`DashboardScreen::
    # CardComponent`, `px-4 py-2.5`), which drew the rule first, so the two
    # look the same.
    #
    # The title is no heading: until 2026-10-31 it was an `h3` in a centred
    # block, which put a level-3 heading saying "No matches" into a screen's
    # outline wherever a list was empty, under whatever level the card stood
    # at. A line of text is what it is; a screen reader reads it where the
    # rows would have been. The title keeps a `data-empty-state-title` hook
    # for a test that must find the title itself, and the root keeps
    # `admin-empty-state`, which tests select by.
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
