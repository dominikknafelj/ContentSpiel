module Admin
  module NotesScreen
    # A person as a NOTE names them: `Admin::Ui::UserNameComponent` with the
    # one difference that someone without a name is the part of their email
    # address before the at sign (`PersonName.of`), not the whole address. Every place a note draws a
    # person's name uses this -- a message's author, a mention's chip, a
    # row's first author, who resolved a thread, who wrote last -- so a
    # person reads the same on all of them. A user who is gone and nobody at
    # all are the shared component's own words.
    class PersonNameComponent < Admin::Ui::UserNameComponent
      def label = @user ? ::PersonName.of(@user) : super
    end
  end
end
