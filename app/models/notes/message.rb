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

    # Of the messages in the relation, only the newest of each CONTAINER (the
    # page, post or image whose screen lists the thread), as its container
    # and its author: `DISTINCT ON (container_type, container_id)`, so
    # however many records are asked about it is one statement and one row
    # each. Active Record has no `distinct_on`, so the select list starts
    # with the node (`Fragments`, as `Audit::Event.newest_per_subject`). It
    # joins, selects and orders: narrow the threads before it (`merge`).
    # Answers "who wrote last on this record?" for the dashboard's Open
    # threads rows.
    scope :newest_per_container, -> {
      threads = Thread.arel_table
      per_container = Arel::Nodes::DistinctOn.new([ threads[:container_type], threads[:container_id] ])
      joins(:thread)
        .select(Arel::Nodes::Fragments.new([ per_container, threads[:container_type] ]), threads[:container_id], arel_table[:author_id])
        .order(threads[:container_type], threads[:container_id], arel_table[:created_at].desc, arel_table[:id].desc)
    }

    before_validation { self.mentioned_user_ids = Mentions.ids(body) }

    validates :body, presence: true, length: { maximum: MAX_BODY }
  end
end
