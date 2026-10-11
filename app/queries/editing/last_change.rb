module Editing
  # Who last changed a block, for the "Updated by Dana Weiss" mark an editor
  # shows when a colleague's save arrives (handoff 10). Read from the audit
  # log, as "Changed by ..." is. The viewer's own change is nobody to name
  # (handoff 22), and so is one made without a user (a token, a job): THE NEWEST
  # CHANGE DECIDES, an older person's is never named in its place. A note on the block and a take-over are not changes
  # (`Dashboard::Feed::NOT_A_CHANGE`).
  module LastChange
    Change = Data.define(:user, :at)

    module_function

    def for(block, viewer:)
      return unless block.persisted?

      event = Audit::Event.where(subject_type: "ContentBlock", subject_id: block.id)
        .where.not(action: Dashboard::Feed::NOT_A_CHANGE)
        .order(last_occurred_at: :desc, id: :desc).includes(:user).first
      return if event.nil? || event.user.nil? || event.user_id == viewer&.id

      Change.new(user: event.user, at: event.last_occurred_at)
    end
  end
end
