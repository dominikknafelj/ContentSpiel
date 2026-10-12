module Admin
  module Ui
    # "Unpublished changes": the rows of a published or scheduled record have
    # moved on from what the site shows (drafts spec §4.4). Full: the status
    # chip's shell with a warn dot, in the editor's header and the posts
    # list. Compact (the page tree, whose column is narrow): the dot alone,
    # named for a screen reader and in a tooltip. Shared by three screens,
    # so it lives here; WHEN to show it is `Publishing::State#changes?`, which
    # the caller asks.
    class UnpublishedChipComponent < AdminComponent
      def initialize(compact: false)
        @compact = compact
      end

      private

      attr_reader :compact
    end
  end
end
