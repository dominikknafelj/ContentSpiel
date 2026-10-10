module Notes
  # One message of a thread: plain text with mention tokens, emoji and URLs
  # (decision D8), never rich text. `mentioned_user_ids` is read from the body
  # before every validation, so the column can't say something the text does
  # not. Whether the mentioned people may be mentioned is the services'
  # question (`Notes::Authorization#mention_errors`), not the record's.
  #
  # The author is nullified when the user is deleted; the message stays and
  # reads "a deleted user" (`Admin::Ui::UserNameComponent`).
  class Message < ApplicationRecord
    self.table_name = "note_messages"

    MAX_BODY = 4_000

    belongs_to :thread, class_name: "Notes::Thread", inverse_of: :messages
    belongs_to :author, class_name: "User", optional: true
    # In the order they were given, so a message's chips stand in the order
    # each emoji first appeared. No `dependent:`: the foreign key removes a
    # message's reactions with it, however the message goes (`delete_all` in
    # `Notes::Remove` runs no callback).
    has_many :reactions, -> { order(:created_at, :id) }, class_name: "Notes::Reaction", foreign_key: :message_id, inverse_of: :message

    # The message's files (notes spec D9, §3.6; `Notes::Files` has the rules
    # and is the one place that attaches them). READ ONLY THROUGH
    # `Admin::NoteFilesController`: never `url`, `rails_blob_path`, a signed
    # id or a variant of one (decision D15) -- Active Storage's read URLs are
    # public to whoever holds one. On a storage service of their own, which
    # those public routes refuse (`Notes::Files::SERVICE`).
    #
    # Whoever deletes a message removes its files first, in its transaction
    # (`Notes::Files.remove`: `Notes::DeleteMessage`, `Notes::Remove`), so
    # the rows go with the note and the bytes when the delete has committed.
    # Active Storage's own `dependent: :purge_later` stays as the net under a
    # destroy that did not come that way (a console).
    has_many_attached :files, service: Files::SERVICE

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
