module Notes
  # Whether one person follows one thread (decision D17). Followers are told
  # of replies, resolves and reopens. `following: false` is an EXPLICIT
  # unfollow, kept so that writing again in the thread does not undo it; only
  # a new mention does. No row at all means the person was never involved.
  # The rules are `Notes::Deliveries.follow`; the button is the service
  # `Notes::SetFollowing`.
  class Follow < ApplicationRecord
    self.table_name = "note_follows"

    belongs_to :thread, class_name: "Notes::Thread"
    belongs_to :user
  end
end
