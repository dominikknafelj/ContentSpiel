module Notes
  # One person's emoji on one message (decision D10): an acknowledgement
  # without a reply. From the fixed set (`Notes::EMOJI`), so nothing a browser
  # sends is ever drawn that the app did not offer. One row per person,
  # message and emoji (the unique index); it goes with its message and with
  # its user (both foreign keys cascade), and it is written by
  # `Notes::React` only.
  class Reaction < ApplicationRecord
    self.table_name = "note_reactions"

    belongs_to :message, class_name: "Notes::Message", inverse_of: :reactions
    belongs_to :user

    validates :emoji, inclusion: { in: Notes::EMOJI }
  end
end
