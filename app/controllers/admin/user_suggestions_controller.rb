module Admin
  # The group editor's member chip input asks this what to offer while an editor
  # types (`Admin::GroupsScreen::MembersComponent`, round 3 Task 11, decision
  # D16): up to `LIMIT` users whose name or email contains the typed text, those
  # that START with it first.
  #
  # Needs `groups.manage` and nothing less (403 otherwise: `forbidden!`, JSON for
  # the fetch). It is the one place CS Studio lists users to someone who may not
  # hold `users.manage`, so it is deliberately not a directory:
  # - a query shorter than `MIN_QUERY_LENGTH` answers nothing, so no empty or
  #   one-letter request lists everyone;
  # - at most eight rows, however broad the text;
  # - owners are never offered ("Owners aren't listed: they already have every
  #   permission"). An owner who is ALREADY a member is rendered as a chip by
  #   the editor itself and stays until removed -- this endpoint plays no part;
  # - each row is only `{ value: id, label: display name, hint: email }`.
  #
  # The text is bound, never interpolated, and `sanitize_sql_like` keeps a typed
  # `%` or `_` literal, as in `Admin::TagSuggestionsController`.
  class UserSuggestionsController < BaseController
    LIMIT = 8
    MIN_QUERY_LENGTH = 2
    # Keeps a pasted paragraph from becoming a huge ILIKE pattern.
    MAX_QUERY_LENGTH = 100

    before_action -> { require_permission("groups.manage") }

    def index
      render json: rows
    end

    private

    def query = params[:q].to_s.strip.first(MAX_QUERY_LENGTH)

    # The ids the members field already holds as chips, a JSON array in
    # `exclude`: left out before the limit, so the field still gets eight to
    # show (with eight matching members already chosen it was offered nobody).
    MAX_EXCLUDED = 100
    def excluded
      list = JSON.parse(params[:exclude].to_s)
      list.is_a?(Array) ? list.first(MAX_EXCLUDED).filter_map { |id| Integer(id, exception: false) } : []
    rescue JSON::ParserError
      []
    end

    def rows
      return [] if query.length < MIN_QUERY_LENGTH

      pattern = User.sanitize_sql_like(query.downcase)
      prefix_first = Arel.sql(ActiveRecord::Base.sanitize_sql_array([
        "(COALESCE(LOWER(users.name), '') LIKE :prefix OR LOWER(users.email_address) LIKE :prefix) DESC", { prefix: "#{pattern}%" }
      ]))
      User.where(owner: false).where.not(id: excluded)
        .where("LOWER(users.name) LIKE :any OR LOWER(users.email_address) LIKE :any", any: "%#{pattern}%")
        .order(prefix_first, Arel.sql("LOWER(users.email_address) ASC"))
        .limit(LIMIT)
        .map { |user| { value: user.id, label: user.display_name, hint: user.email_address } }
    end
  end
end
