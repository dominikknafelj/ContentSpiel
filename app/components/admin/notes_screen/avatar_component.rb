module Admin
  module NotesScreen
    # A person as a round avatar with their initials (a note's message and its thread row; an audit sentence's actor is drawn by
    # `Admin::Ui::ActorAvatarComponent`, on the same shared circle). Two letters: a two-word name gives each word's first, a one-word name its first two (`PersonName.initials`). The viewer's own is the solid people fill; everyone else's
    # is the people tint. Decoration only: the name is always written
    # beside it, so it is hidden from a screen reader.
    class AvatarComponent < Admin::AdminComponent
      SIZES = { row: :md, message: :sm }.freeze

      def initialize(user:, user_id:, viewer:, size:)
        @user = user
        @user_id = user_id
        @viewer = viewer
        @size = SIZES.fetch(size)
      end

      # The circle itself is the shared one (`Admin::Ui::AvatarComponent`). A
      # deleted user is nobody to name: the empty circle, with no letters and no
      # people colour.
      def call
        return render(Admin::Ui::AvatarComponent.new(initials: "", size: @size, tone: :empty)) if @user.nil?

        render(Admin::Ui::AvatarComponent.new(initials: initials, size: @size, tone: own? ? :own : :other))
      end

      private

      # The two letters (`PersonName.initials`) of whatever names the person
      # in a note (`PersonNameComponent`: the name, else the part of the
      # email address before the at sign): the shared rule,
      # `PersonName.initials`. A deleted user never gets here (`call`).
      def initials
        PersonName.initials(Admin::NotesScreen::PersonNameComponent.new(user: @user, user_id: @user_id).label)
      end

      def own? = @viewer.present? && @user.present? && @user.id == @viewer.id
    end
  end
end
