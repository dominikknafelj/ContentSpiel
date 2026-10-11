module Admin
  # The one toast a bulk action on a list answers with (design pass round 2,
  # Task 17): how many were done, and -- each its own sentence, plural-correct
  # -- which were left alone and why. Shared by the posts list's `bulk` and the
  # trash's `restore_many` (a bulk trash's Undo), so both speak in the same
  # shapes:
  #
  # - "Published 3 posts."
  # - "Published 2 posts. 1 was already live. 1 scheduled post was left as scheduled."
  # - "Published 2 posts. 1 was refused: “Title”." (a permission denial)
  # - "Published 2 posts. 1 couldn't be published: “Title” (Content type is not registered)." (any other failure, with the first reason)
  # - "Moved 3 posts to the trash." (with Undo)
  # - "Nothing was changed. 2 posts were not found."
  #
  # Something done and nothing wrong is a success toast (`flash[:notice]`);
  # something done AND something refused, failed or not found is a warning
  # toast (`flash[:warning]`), because the toast is the only place the
  # failures are named and a warning never auto-hides (a success one goes
  # after 4 s, an Undo one after 8); nothing done, with something refused,
  # failed or not found, is an error toast (`flash[:alert]`). An id that names no kept post the viewer can read is
  # only ever *counted* -- never named -- so a hidden post's existence isn't
  # disclosed ("not found, not forbidden").
  #
  # Everything that travels in the flash is bounded: it lives in the session
  # cookie (4 KB), so a title is cut to TITLE_LENGTH, a reason to
  # REASON_LENGTH, at most NAMED_PER_SENTENCE are named, and an Undo URL
  # (which carries the list's filters, free text among them) is offered only
  # up to MAX_UNDO_URL bytes -- else the toast says where to find the posts.
  module BulkResponses
    NAMED_PER_SENTENCE = 3
    TITLE_LENGTH = 60
    REASON_LENGTH = 120
    MAX_UNDO_URL = 1_500
    # The whole of what rides in the session cookie for one bulk answer: the
    # sentences plus the Undo URL, in BYTES (titles and the search text are
    # multi-byte; the cookie's limit is 4 KB for everything the session
    # holds). Over it, the Undo is dropped and the toast says where to find
    # the posts instead.
    MAX_FLASH_BYTES = 2_000

    private

    def undo_offered?(url) = url.bytesize <= MAX_UNDO_URL

    # `failed_phrase` completes "couldn't be ..." ("published", "moved to the
    # trash", "restored").
    def flash_bulk_result(done:, verb:, failed_phrase:, refused: [], failed: [], reasons: {}, already_live: [], skipped_scheduled: [],
                          held: 0, not_found: 0, suffix: "", undo_url: nil, undo_dropped: false)
      sentences = [ done.any? ? "#{verb} #{helpers.pluralize(done.size, "post")}#{suffix}." : "Nothing was changed." ]
      sentences << "#{counted(already_live.size, "was", "were")} already live." if already_live.any?
      sentences << "#{helpers.pluralize(skipped_scheduled.size, "scheduled post")} #{skipped_scheduled.size == 1 ? "was" : "were"} left as scheduled." if skipped_scheduled.any?
      sentences << "#{helpers.pluralize(held, "post")} being edited by someone #{held == 1 ? "was" : "were"} skipped." if held.positive?
      sentences << "#{counted(refused.size, "was", "were")} refused: #{names(refused)}." if refused.any?
      if failed.any?
        reason = reasons[failed.first.id].to_s.truncate(REASON_LENGTH)
        sentences << "#{failed.size} couldn't be #{failed_phrase}: #{names(failed)}#{" (#{reason})" if reason.present?}."
      end
      sentences << "#{helpers.pluralize(not_found, "post")} #{not_found == 1 ? "was" : "were"} not found." if not_found.positive?
      over_budget = undo_url && (sentences.sum(&:bytesize) + sentences.size + undo_url.bytesize) > MAX_FLASH_BYTES
      undo_url = nil if over_budget
      sentences << "Find them in the Trash." if (undo_dropped || over_budget) && done.any?

      problem = refused.any? || failed.any? || not_found.positive?
      flash[!problem ? :notice : (done.any? ? :warning : :alert)] = sentences.join(" ")
      flash[:undo] = { "label" => "Undo", "url" => undo_url } if undo_url && done.any?
    end

    def counted(count, one, many) = count == 1 ? "1 #{one}" : "#{count} #{many}"

    def names(posts)
      listed = posts.first(NAMED_PER_SENTENCE).map { |post| "“#{(post.title(locale: admin_locale).presence || "(untitled)").truncate(TITLE_LENGTH)}”" }
      rest = posts.size - listed.size
      rest.positive? ? "#{listed.join(", ")} and #{rest} more" : listed.to_sentence
    end
  end
end
