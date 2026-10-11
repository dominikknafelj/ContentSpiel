module Notes
  # One conversation on one record (notes spec §3.1, decision D1): it can be
  # replied to, resolved, reopened and pinned. Its first message is the note
  # that started it; a thread with no message does not exist
  # (`Notes::DeleteMessage` deletes the thread with its last one).
  #
  # `subject` is what the thread is about. `container` is the record whose
  # screen lists it and whose permissions it follows -- for a block, the
  # block's page. It is DERIVED here from the subject on every save, never
  # taken from a caller: a thread filed under a page its block does not belong
  # to would be readable by the wrong people.
  #
  # Both references are polymorphic, so there is no foreign key and no
  # `has_many` on the content side (`test/lib/notes_boundary_test.rb`):
  # `Notes::Remove` deletes a record's threads when the record goes for good.
  # A trashed record keeps its threads; every read narrows through the read
  # scope, which hides the trash.
  class Thread < ApplicationRecord
    self.table_name = "note_threads"

    STATES = %w[open resolved].freeze
    # Where the thread was started. Context only ("written on German"), never
    # used to decide where a thread appears.
    # `list` is RESERVED: no surface sends it yet (the posts list and the
    # page tree show counts and start no note); it stays so that a thread
    # started from one later needs no migration of what the column allows.
    ORIGIN_VIEWS = %w[editor mind_graph media list].freeze
    MAX_QUOTE = 500

    belongs_to :subject, polymorphic: true
    belongs_to :container, polymorphic: true
    belongs_to :created_by, class_name: "User", optional: true
    belongs_to :resolved_by, class_name: "User", optional: true
    belongs_to :pinned_by, class_name: "User", optional: true
    # Oldest first: the order a thread is read in. `dependent: :destroy` so a
    # message's own callbacks run; the deliveries and reactions go by their
    # foreign keys. A message's files are removed by whoever deletes it,
    # before the delete (`Notes::Files.remove`): `Notes::DeleteMessage`, and
    # `Notes::Remove`, which deletes threads with one DELETE and no callback.
    has_many :messages, -> { order(:created_at, :id) }, class_name: "Notes::Message", foreign_key: :thread_id,
      inverse_of: :thread, dependent: :destroy

    before_validation :derive_container

    validates :subject_type, inclusion: { in: ->(_thread) { Notes.subject_types } }
    validates :state, inclusion: { in: STATES }
    validates :origin_view, inclusion: { in: ORIGIN_VIEWS }
    validates :quote, length: { maximum: MAX_QUOTE }
    validates :last_message_at, presence: true

    # Not `open`: `Kernel#open` is a method of every class.
    scope :unresolved, -> { where(state: "open") }
    scope :resolved, -> { where(state: "resolved") }

    def open? = state == "open"

    def resolved? = state == "resolved"

    def first_message = messages.first

    private

    def derive_container
      self.container = Notes.container_for(subject) if subject
    end
  end
end
