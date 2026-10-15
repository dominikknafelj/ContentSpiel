module Admin
  module Ui
    # "Unpublished changes": the rows of a published or scheduled record have
    # moved on from what the site shows (drafts spec §4.4). The status chip's
    # shell with a warn dot, in the editor's header and the posts list; the
    # page tree draws its own mark (`Admin::PagesScreen::TreeStateMarkComponent`).
    # Shared by two screens, so it lives here; WHEN to show it is `Publishing::State#changes?`, which
    # the caller asks.
    class UnpublishedChipComponent < AdminComponent
    end
  end
end
