module Admin
  module Ui
    # "No address": a live page or post the site has no address for, because
    # another record holds it (drafts plan, task 6, addition 3). The status
    # chip's shell with a warn dot, and the sentence in its
    # tooltip. WHEN to show it is `Publishing::Addressless`, which the caller
    # asks.
    class NoAddressChipComponent < AdminComponent
    end
  end
end
