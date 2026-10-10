module Admin
  # The shared shape of a list's filter form (design pass spec §4): a GET form
  # that applies as you change it (`admin--ui--auto-submit`) and reloads only the
  # `content` frame, replacing the history entry rather than adding one per
  # keystroke pause. The controller's actions sit on the form so every field
  # in it -- select, date, text -- is covered without per-field wiring: a
  # `change` submits at once, `input` (typing) waits for the delay. Text
  # inputs need a stable `id` (the field helpers' defaults give one) so focus
  # and caret can be restored after the reload.
  module FilterHelper
    FILTER_ACTIONS = "change->admin--ui--auto-submit#submit input->admin--ui--auto-submit#submitLater".freeze

    # `frame:` is the Turbo Frame the answer renders in. The default is the
    # screen's `content` frame, with the history entry replaced rather than one
    # added per keystroke pause; any other frame (the media picker's own grid,
    # inside a dialog) is not a page, so it never promotes the navigation to a
    # visit -- `turbo_action` would change the URL under the editor.
    def filter_form_options(url, frame: "content")
      data = { controller: "admin--ui--auto-submit", action: FILTER_ACTIONS, turbo_frame: frame }
      data[:turbo_action] = "replace" if frame == "content"
      { url: url, method: :get, class: "mb-4 flex flex-wrap items-end gap-3", data: data }
    end

    def filters_active?(keys) = keys.any? { |key| params[key].present? }

    # "type blog, status draft, title “zzz”" -- the active filters named for a
    # "No matches" empty state, from `{ label => param key }`.
    def filter_summary(labels)
      labels.filter_map { |label, key| "#{label} #{params[key]}" if params[key].present? }.to_sentence
    end
  end
end
