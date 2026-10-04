module Posts
  # Publishes or trashes a selection of posts from the posts list (design pass
  # round 2, Task 17). It writes nothing itself: every post goes through the
  # single-record service that already owns the rule -- `Posts::Save` for
  # "publish", `Trash::Move` for "trash" -- so each post gets its own
  # authorisation with its own scope (content type, `own`, "editing a
  # published record needs `publish`", a publish-only change needs only
  # `publish`), its own audit event, its own `public_paths`/media-usage/
  # translation-state side effects and its own `updated_at`. Re-implementing
  # any of that here would be a second copy of the permission rules.
  #
  # The ids come from the client, so they are loaded ONLY through
  # `AccessControl.scope(actor, "posts.read", ...)` (kept posts the actor may
  # read): an id that doesn't exist, is trashed or lies outside the actor's
  # read scope is *not found* -- counted, never named, never refused (the
  # "not found, not forbidden" rule: a locked-out post's existence isn't
  # disclosed). A post the actor may read but not act on comes back in
  # `refused` (the service's own denial recorded one `access.denied` for it).
  #
  # No all-or-nothing: a bulk publish that fails for one post must not
  # unpublish nine. Each post runs in its own savepoint (the services open
  # one themselves; the extra one here also covers an exception out of a
  # service or a callback, which then counts as that post's failure and rolls
  # back only that post's writes), and the first problem never stops the
  # rest. `reasons` maps a refused post's id to the message to show for it.
  #
  # Bounded: at most MAX_IDS distinct ids per call -- more is a programming
  # error (`ArgumentError`; the controller answers 422), as is an unknown
  # action. A duplicated id counts once.
  #
  # audit: none (each post's own service records its event; nothing is
  # written here that has no event of its own)
  class Bulk < ApplicationService
    ACTIONS = %w[publish trash].freeze
    MAX_IDS = 200
    # A bigint column's largest id has 19 digits; anything longer (or not
    # digits at all) can't be a post and must not reach the query.
    ID_FORMAT = /\A\d{1,18}\z/

    Result = Data.define(:done, :refused, :not_found, :reasons)

    def initialize(action:, ids:, actor: Current.actor)
      raise ArgumentError, "unknown bulk action #{action.inspect}" unless ACTIONS.include?(action.to_s)

      @action = action.to_s
      @ids = Array(ids).map(&:to_s).uniq
      raise ArgumentError, "at most #{MAX_IDS} posts per call" if @ids.size > MAX_IDS

      @actor = actor
    end

    def call
      posts = readable_posts
      done = []
      refused = []
      reasons = {}

      posts.each do |post|
        result = act_on(post)
        if result.ok?
          done << post
        else
          refused << post
          reasons[post.id] = result.errors.to_sentence
        end
      end

      Result.new(done:, refused:, not_found: @ids.size - posts.size, reasons:)
    end

    private

    def readable_posts
      numeric = @ids.grep(ID_FORMAT)
      return [] if numeric.empty?

      AccessControl.scope(actor, "posts.read", Post.where(id: numeric)).order(:id).to_a
    end

    # A failed *result* is not rolled back here: the services already undid
    # their own writes, and a denial's `access.denied` event is recorded
    # outside their transaction precisely so it survives -- a savepoint
    # around it would swallow it. Only an exception rolls the post's savepoint
    # back.
    def act_on(post)
      Post.transaction(requires_new: true) { perform(post) }
    rescue StandardError => e
      Rails.logger.error("Posts::Bulk #{@action} failed for post #{post.id}: #{e.class}: #{e.message}")
      ApplicationService::Result.failure(post, [ "It couldn't be #{@action == "trash" ? "moved to the trash" : "published"}" ])
    end

    def perform(post)
      case @action
      when "publish" then Posts::Save.call(post, attributes: { published: true }, actor:)
      when "trash" then Trash::Move.call(post, actor:)
      end
    end
  end
end
