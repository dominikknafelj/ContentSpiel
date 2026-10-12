module Editing
  # What live editing says, and to whom (live-editing spec §3.1, §4.2).
  #
  # THE SOURCE IS THE AUDIT LOG. Every content write records an event, and
  # `Audit.record` publishes `Audit::NOTIFICATION` once the outermost
  # transaction has committed, also for an event coalesced into an earlier
  # one. `heard` is subscribed to it (`config/initializers/editing.rb`) and
  # maps the event's ACTION to a signal, so no content service names this
  # feature, and a write through the MCP server or the console is covered like
  # one from CS Studio. `MAP` and `SILENT` together hold every action in
  # `Audit::Sentence::ACTIONS` (`test/models/editing/signals_test.rb` fails
  # for one neither knows): a new write path is covered by a line here, not by
  # a call someone has to remember.
  #
  # A SIGNAL SAYS ONLY THAT SOMETHING CHANGED: `kind` "content", the block's
  # id (nil for the record itself and for the list's structure), a `reason`
  # and the tab that caused it. Never text. It is sent on the stream of the
  # page or post, to which `Editing::Channel` subscribes through the read
  # scope, and what it leads to is fetched through that scope again.
  #
  # NEVER RAISES. It runs inside the request that made the write, after the
  # commit: an exception here would turn a saved block into an error page.
  module Signals
    SAVED = "saved".freeze
    STRUCTURE = "structure".freeze
    GONE = "gone".freeze

    MAP = {
      "page.updated" => SAVED, "page.published" => SAVED, "page.changes_published" => SAVED, "post.changes_published" => SAVED, "page.unpublished" => SAVED, "page.moved" => SAVED,
      "page.translation_confirmed" => SAVED, "page.trashed" => GONE, "page.purged" => GONE,
      "post.updated" => SAVED, "post.published" => SAVED, "post.unpublished" => SAVED, "post.scheduled" => SAVED,
      "post.translation_confirmed" => SAVED, "post.trashed" => GONE, "post.purged" => GONE,
      "block.created" => STRUCTURE, "block.deleted" => STRUCTURE, "block.reordered" => STRUCTURE,
      "block.updated" => SAVED, "block.translation_confirmed" => SAVED
    }.freeze

    SILENT = {
      "page.created" => "nobody has an editor open on a page that did not exist",
      "post.created" => "nobody has an editor open on a post that did not exist",
      "page.restored" => "a trashed page has no open editor: its editor answers 404",
      "post.restored" => "a trashed post has no open editor: its editor answers 404",
      "ai.translated" => "it writes nothing: the suggestions go to the tab that asked",
      "media.uploaded" => "library images are not live in this step (spec section 9)",
      "media.updated" => "library images are not live in this step (spec section 9)",
      "media.trashed" => "library images are not live in this step (spec section 9)",
      "media.restored" => "library images are not live in this step (spec section 9)",
      "media.purged" => "library images are not live in this step (spec section 9)",
      "media.translation_confirmed" => "library images are not live in this step (spec section 9)",
      "settings.translation_confirmed" => "site settings are saved explicitly and have no live editor",
      "settings.updated" => "site settings are saved explicitly and have no live editor",
      "page.taken_over" => "a take-over sends its own holder signal (Editing::TakeOver)",
      "post.taken_over" => "a take-over sends its own holder signal (Editing::TakeOver)",
      "block.taken_over" => "a take-over sends its own holder signal (Editing::TakeOver)",
      "tag.renamed" => "it touches the posts that carry the tag; their open forms are refused as stale, as before (roadmap)",
      "tag.deleted" => "it touches the posts that carry the tag; their open forms are refused as stale, as before (roadmap)",
      "tag.merged" => "it touches the posts that carry the tag; their open forms are refused as stale, as before (roadmap)"
    }.merge(
      (Audit::Sentence::NOTE_VERBS.keys + Audit::Sentence::SPECIAL_ACTIONS).index_with { "not a change to a page's or a post's content" },
      %w[user.created user.updated user.deleted group.created group.updated group.deleted token.issued token.revoked]
        .index_with { "an account, a group or a token is not content" }
    ).freeze

    module_function

    def record_stream(record) = stream_for(record.class.polymorphic_name, record.id)

    # The one spelling of a record's stream, from its type name and id.
    def stream_for(type, id) = "editing:record:#{type.to_s.delete(":")}-#{id}"

    # The audit notification's listener.
    def heard(event)
      reason = MAP[event.action]
      unless reason
        raise ArgumentError, "Editing::Signals knows no action #{event.action.inspect}" unless SILENT.key?(event.action)

        return
      end

      type, id, block_id = place(event)
      return unless type && id

      structural = structural?(event)
      block_id = nil unless reason == SAVED && !structural
      reason = STRUCTURE if structural
      send_to(stream_for(type, id), kind: "content", content_block_id: block_id, reason:)
      # A trashed branch is ONE event on its root (`descendant_ids`): an editor
      # open on a child page is told too.
      descendants(event).each { |child_id| send_to(stream_for("Page", child_id), kind: "content", content_block_id: nil, reason:) }
    rescue StandardError => error
      Rails.logger.warn("Editing signal not sent (#{event&.action}): #{error.class}")
      Rails.error.report(error, handled: true)
    end

    # A change of holder (spec §4.2): every other tab fetches that card again.
    def holder(record, subject, reason)
      send_to(record_stream(record), kind: "holder", content_block_id: (subject.id if subject.is_a?(ContentBlock)), reason:)
    end

    def send_to(stream, payload)
      origin = Current.editing_tab.to_s[Live::Signals::TAB]
      Live::Signals.later(stream, origin ? payload.merge(origin:) : payload)
    end

    # [ owner type, owner id, block id ] of the page or post an event is about.
    # A block that still exists is read from its row (one indexed read, after
    # the commit); a deleted one from the metadata `ContentBlocks::Destroy`
    # writes. A block of a post has no editor of its own and no signal.
    def place(event)
      return [ event.subject_type, event.subject_id, nil ] unless event.subject_type == "ContentBlock"

      if event.action == "block.deleted"
        page_id = event.metadata.to_h["page_id"]
        return page_id.is_a?(Integer) ? [ "Page", page_id, nil ] : nil
      end

      owner_type, owner_id = ContentBlock.where(id: event.subject_id).pick(:owner_type, :owner_id)
      owner_type == "Page" ? [ "Page", owner_id, event.subject_id ] : nil
    end

    def descendants(event)
      return [] unless event.action == "page.trashed"

      Array(event.metadata.to_h["descendant_ids"]).grep(Integer)
    end

    # A save that moved blocks between a section's columns (a fold) redraws the
    # list, like a move. The fold's own row is never coalesced INTO (it is
    # created with `coalesce: false`), but a later plain save of the same
    # section extends that row, whose metadata still holds `folded_block_ids`:
    # such a row has `occurrences` above 1, and this write was not the fold.
    def structural?(event)
      event.action == "block.updated" && event.occurrences.to_i <= 1 && event.metadata.to_h["folded_block_ids"].present?
    end

    private_class_method :send_to, :place, :structural?, :descendants, :stream_for
  end
end
