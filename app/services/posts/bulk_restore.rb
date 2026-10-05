module Posts
  # The Undo of a bulk trash (`POST /trash/restore_many`, Task 17): brings the
  # named trashed posts back, one `Trash::Restore` each, so each is authorised
  # (the delete right with its scope), audited and answered on its own. Same
  # contract as `Posts::Bulk`:
  #
  # - ids load ONLY through `AccessControl.scope(..., "posts.delete",
  #   trashed: true)` -- the trashed posts the actor may act on; an id that is
  #   kept, gone, of another type or out of scope is *not found*, counted and
  #   never named;
  # - each post runs in its own savepoint with its own rescue: an exception
  #   out of one restore rolls back only that post and counts it as failed, a
  #   refusal (`denied`) as refused, and neither stops the rest;
  # - at most `Posts::Bulk::MAX_IDS` distinct ids (`ArgumentError`), integers
  #   deduplicated as in `Posts::Bulk.normalize_ids`.
  #
  class BulkRestore < ApplicationService
    # authorize: none (the ids load through AccessControl.scope; each post's own Trash::Restore authorizes it)
    # audit: none (each post's own Trash::Restore records its event; a refusal is its access.denied, an unreadable id is not found and leaves no trace)
    Result = Data.define(:restored, :refused, :failed, :not_found, :reasons)

    def initialize(ids:, actor: Current.actor)
      @ids = Posts::Bulk.normalize_ids(ids)
      raise ArgumentError, "at most #{Posts::Bulk::MAX_IDS} posts per call" if @ids.size > Posts::Bulk::MAX_IDS

      @actor = actor
    end

    def call
      posts = trashed_posts
      restored, refused, failed, reasons = [], [], [], {}

      posts.each do |post|
        result = restore(post)
        if result.ok?
          restored << post
        else
          (result.denied? ? refused : failed) << post
          reasons[post.id] = result.errors.to_sentence
        end
      end

      Result.new(restored:, refused:, failed:, not_found: @ids.size - posts.size, reasons:)
    end

    private

    def trashed_posts
      numeric = @ids.grep(Integer)
      return [] if numeric.empty?

      AccessControl.scope(actor, "posts.delete", Post.where(id: numeric), trashed: true).order(:id).to_a
    end

    # As `Posts::Bulk#act_on`: a failed result is left alone (a denial's
    # event must survive), only an exception rolls the savepoint back.
    def restore(post)
      Post.transaction(requires_new: true) { Trash::Restore.call(post, actor:) }
    rescue StandardError => e
      Rails.logger.error("Posts::BulkRestore failed for post #{post.id}: #{e.class}: #{e.message}")
      ApplicationService::Result.failure(post, [ "It couldn't be restored" ])
    end
  end
end
