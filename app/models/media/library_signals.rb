module Media
  # What the library says to its other tabs (media-folders spec §11): THAT the
  # folders changed or images moved, never which. The stream is one for the
  # whole library, not per record, so the payload names no folder, image or
  # word -- a tab that hears it fetches the tree and the grid again through
  # its own scoped requests. Sent through `Live::Signals.later`, after the
  # outermost commit, so a refusal or a rollback sends nothing. An upload
  # sends nothing: the tab that made it shows it already.
  module LibrarySignals
    STREAM = "media:library".freeze

    module_function

    # reason: "folders" (a folder made, renamed, moved or deleted) or "moved" (images changed folder).
    def changed(reason:)
      Live::Signals.later(STREAM, { kind: "library", reason: reason, origin: origin }.compact)
    end

    # The acting tab (`Current.editing_tab`, the header `X-Notes-Tab` that
    # `Admin::BaseController` reads for every CS Studio request), so that tab
    # does not fetch again what its own answer drew. Not `notes_tab`, which
    # only the notes controllers set.
    def origin = Current.editing_tab.to_s[Live::Signals::TAB]
  end
end
