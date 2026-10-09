module Notes
  # One line of one person's inbox (notes spec §3.3): "this message is for
  # you, because …". At most one per person and message (the unique index).
  # Written by `Notes::Deliveries` inside the transaction of the message;
  # read when its owner opens the record's notes or presses "Mark all read"
  # (`Notes::MarkRead`). A row is kept when its owner loses the right to read
  # the record; the inbox narrows through `Notes.readable_threads` and simply
  # stops showing it.
  class Delivery < ApplicationRecord
    self.table_name = "note_deliveries"

    REASONS = %w[mention reply resolved reopened].freeze

    belongs_to :user
    belongs_to :message, class_name: "Notes::Message"
    belongs_to :thread, class_name: "Notes::Thread"

    validates :reason, inclusion: { in: REASONS }

    scope :unread, -> { where(read_at: nil) }

    # Does `thread` hold a delivery `user` has not read? One EXISTS (the
    # thread's rows by `thread_id`, or the user's unread ones by `user_id,
    # read_at`: both are indexed), no query without a user. What opening a thread asks
    # before it marks anything read (`Admin::NoteThreadsController#show`).
    def self.unread_on?(thread, user)
      user.present? && unread.exists?(user_id: user.id, thread_id: thread.id)
    end
  end
end
