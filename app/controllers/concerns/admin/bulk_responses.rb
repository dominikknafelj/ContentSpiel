module Admin
  # The one toast a bulk action on a list answers with (design pass round 2,
  # Task 17): how many were done, which were refused (by title -- the viewer
  # could read them, or they would have been "not found"), and how many ids
  # named nothing the viewer can act on at all. Shared by the posts list's
  # `bulk` and the trash's `restore_many` (a bulk trash's Undo), so both speak
  # in the same four shapes:
  #
  # - "Published 3 posts."
  # - "Published 2 posts. 1 was refused: “Title”."
  # - "Moved 3 posts to the trash." (with Undo)
  # - "Nothing was changed. 2 posts were not found."
  #
  # Something done is a success toast (`flash[:notice]`); nothing done is an
  # error toast (`flash[:alert]`). An id that names no kept post the viewer can
  # read is only ever *counted* -- never named -- so a hidden post's existence
  # isn't disclosed ("not found, not forbidden").
  module BulkResponses
    # Names listed in a "refused" sentence before it says "and N more".
    NAMED_REFUSALS = 3
    # An Undo URL carries the ids (and sits in the session cookie, 4 KB): a
    # page of the list is at most 50, so Undo is offered up to that and left
    # out for a bigger batch only an API client could send.
    MAX_UNDO_IDS = 50

    private

    def undo_offered?(done) = done.any? && done.size <= MAX_UNDO_IDS

    def flash_bulk_result(done:, refused:, not_found:, verb:, suffix: "", undo_url: nil)
      sentences = [ done.any? ? "#{verb} #{helpers.pluralize(done.size, "post")}#{suffix}." : "Nothing was changed." ]
      sentences << "#{refused.size == 1 ? "1 was" : "#{refused.size} were"} refused: #{refused_names(refused)}." if refused.any?
      sentences << "#{helpers.pluralize(not_found, "post")} #{not_found == 1 ? "was" : "were"} not found." if not_found.positive?

      flash[done.any? ? :notice : :alert] = sentences.join(" ")
      flash[:undo] = { "label" => "Undo", "url" => undo_url } if undo_url && done.any?
    end

    def refused_names(refused)
      names = refused.first(NAMED_REFUSALS).map { |post| "“#{post.title(locale: admin_locale).presence || "Untitled"}”" }
      rest = refused.size - names.size
      rest.positive? ? "#{names.join(", ")} and #{rest} more" : names.to_sentence
    end
  end
end
