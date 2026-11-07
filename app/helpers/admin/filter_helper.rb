module Admin
  # The shared shape of a list's filter form: a GET form
  # that applies as you change it (`admin--ui--auto-submit`) and reloads only the
  # `content` frame, replacing the history entry rather than adding one per
  # keystroke pause. The controller's actions sit on the form so every field
  # in it -- select, date, text -- is covered without per-field wiring: a
  # `change` submits at once, `input` (typing) waits for the delay. Text
  # inputs need a stable `id` (the field helpers' defaults give one) so focus
  # and caret can be restored after the reload.
  module FilterHelper
    FILTER_ACTIONS = "change->admin--ui--auto-submit#submit input->admin--ui--auto-submit#submitLater".freeze
    # The bar's own look: one wrapping row whose controls the stylesheet holds
    # to one height (`.admin-filter-bar`).
    BAR_CLASS = "admin-filter-bar mb-4 flex flex-wrap items-start gap-3".freeze

    # `frame:` is the Turbo Frame the answer renders in. The default is the
    # screen's `content` frame, with the history entry replaced rather than one
    # added per keystroke pause; any other frame (the media picker's own grid,
    # inside a dialog) is not a page, so it never promotes the navigation to a
    # visit -- `turbo_action` would change the URL under the editor.
    #
    # `bar: false` draws the form as `contents`, for a form that holds more
    # than its bar (the posts list's, whose filter panel stands in the list's
    # rail): the form's children are then its parent's layout items, and the
    # caller draws the bar itself with `BAR_CLASS`.
    def filter_form_options(url, frame: "content", bar: true)
      data = { controller: "admin--ui--auto-submit", action: FILTER_ACTIONS, turbo_frame: frame }
      data[:turbo_action] = "replace" if frame == "content"
      { url: url, method: :get, class: bar ? BAR_CLASS : "contents", data: data }
    end

    def filters_active?(keys) = keys.any? { |key| params[key].present? }
  end
end
