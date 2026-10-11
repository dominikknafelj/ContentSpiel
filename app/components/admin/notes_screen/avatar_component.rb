module Admin
  module NotesScreen
    # A person as a round avatar with their initials (handoff "Message",
    # "Thread row in the list"; the dashboard's activity row draws the same
    # shape with one letter). The viewer's own is filled ink; everyone else's
    # is sunken with a line. Decoration only: the name is always written
    # beside it, so it is hidden from a screen reader.
    class AvatarComponent < Admin::AdminComponent
      SIZES = { row: :md, message: :sm }.freeze

      def initialize(user:, user_id:, viewer:, size:)
        @user = user
        @user_id = user_id
        @viewer = viewer
        @size = SIZES.fetch(size)
      end

      # The circle itself is the shared one (`Admin::Ui::AvatarComponent`).
      def call = render(Admin::Ui::AvatarComponent.new(initials: initials, size: @size, tone: own? ? :own : :other))

      private

      # The first letters of the first two words of whatever names the person
      # in a note (`PersonNameComponent`: the name, else the part of the
      # email address before the at sign, else "a deleted user"): the shared
      # rule, `PersonName.initials`.
      def initials
        PersonName.initials(Admin::NotesScreen::PersonNameComponent.new(user: @user, user_id: @user_id).label)
      end

      def own? = @viewer.present? && @user.present? && @user.id == @viewer.id
    end
  end
end
