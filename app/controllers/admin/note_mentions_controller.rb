module Admin
  # Whom a note on this record can mention (notes spec §3.2): the users who
  # may READ it, by the name a note gives them (`Notes.name_of`: someone
  # without a name is the part of their address before the at sign, the
  # handoff's decision 36) with the whole email address as the hint on the
  # second line, always. The second place CS Studio
  # lists users to someone without `users.manage`, and like
  # `Admin::UserSuggestionsController` deliberately not a directory: six rows
  # at most, and only for a record the asker may read (`NoteContainer`) --
  # whoever may read a page may learn who else can, six names at a time. The
  # picker opens on "@" alone, so an empty query answers the first six.
  # Owners are offered: an owner reads everything.
  #
  # The read right has no SQL form across users, so the best `CANDIDATES`
  # matches are judged one by one; a site where more than that many people
  # match and few of them may read the record shows fewer than six, and one
  # more letter finds the rest.
  #
  # The text is bound, never interpolated, and `User.name_or_email_containing`
  # keeps a typed `%` or `_` literal.
  class NoteMentionsController < BaseController
    include NoteContainer

    LIMIT = 6
    CANDIDATES = 40
    # Keeps a pasted paragraph from becoming a huge ILIKE pattern.
    MAX_QUERY_LENGTH = 100

    def index
      query = params[:q].to_s.strip.first(MAX_QUERY_LENGTH)
      # Only people who can sign in: an invited person could not read the note.
      people = User.can_sign_in
      matching = query.empty? ? people : people.name_or_email_containing(query).name_or_email_starting_first(query)
      users = matching.by_email.limit(CANDIDATES).select { |user| Notes.readable?(user, @container, channel: :admin) }.first(LIMIT)
      render json: users.map { |user| { id: user.id, label: Notes.name_of(user), hint: user.email_address, initials: PersonName.initials(Notes.name_of(user)) } }
    end
  end
end
