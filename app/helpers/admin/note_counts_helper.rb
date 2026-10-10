module Admin
  # The open notes of library images as a list shows them (notes spec §4.4):
  # the media grid's tiles, and the one tile an autosave in the panel draws
  # again. One method for both, so the question "may this viewer know about
  # an image's notes at all" is asked in one place.
  module NoteCountsHelper
    # `[ { asset id => open threads }, Set<asset ids with something unread
    # for the viewer> ]` for the images named: one grouped query and one
    # beside it, whatever their number (`Notes::Counts`).
    #
    # Nothing for a viewer without `media.upload`. That right alone is the
    # gate of an image's notes (`Admin::NoteContainer#set_container`, a 403),
    # and not every screen that draws a tile has it for a gate: `PATCH
    # /media/:id` also lets `media.manage` through by itself
    # (`Admin::MediaController`), and the tile it answers with must not count
    # notes its reader could not open. `Notes::Counts` hides nothing itself:
    # the caller hands over kept images only (`Media::Search#results`,
    # `Media::Asset.kept`).
    def media_note_marks(asset_ids)
      return [ {}, Set.new ] unless can?("media.upload")

      [ Notes::Counts.by_container("Media::Asset", asset_ids), Notes::Counts.unread_among("Media::Asset", asset_ids, Current.user) ]
    end
  end
end
