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
  end
end
