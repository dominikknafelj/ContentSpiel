module Notes
  # One message of a thread: plain text with mention tokens, emoji and URLs
  # (decision D8), never rich text. `mentioned_user_ids` is read from the body
  # before every validation, so the column can't say something the text does
  # not. Whether the mentioned people may be mentioned is the services'
  # question (`Notes::Authorization#mention_errors`), not the record's.
  #
  # The author is nullified when the user is deleted; the message stays and
  # reads "a deleted user" (`Admin::UserNameComponent`).
  class Message < ApplicationRecord
    self.table_name = "note_messages"

    MAX_BODY = 4_000

    belongs_to :thread, class_name: "Notes::Thread", inverse_of: :messages
    belongs_to :author, class_name: "User", optional: true

    before_validation { self.mentioned_user_ids = Mentions.ids(body) }

    validates :body, presence: true, length: { maximum: MAX_BODY }
  end
end
