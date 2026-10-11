module Editing
  # The live reservations of one page or post, read ONCE for a whole screen:
  # every card, tile and form asks this object, so an editor costs the same
  # statements for 3 blocks as for 30: up to three (the rows, then their users,
  # then their requesters), however many blocks there are. `viewer` and `tab` say whose screen it is: a hold
  # is OTHER unless it is this person's in this very tab (their other tab is
  # someone else, and so is everyone when the tab is unknown). A row carries
  # its holder (`user`, `tab`) and its pending request (`requested_by`,
  # `requested_tab`), which is all a card needs to say who holds it.
  class Holds
    def self.on(record, viewer:, tab:, now: Time.current)
      rows = Reservation.on(record).live(now).includes(:user, :requested_by).to_a.select(&:user)
      new(rows, viewer:, tab:)
    end

    def self.none = new([], viewer: nil, tab: nil)

    def initialize(rows, viewer:, tab:)
      @rows = rows.index_by { |row| [ row.subject_type, row.subject_id ] }
      @viewer = viewer
      @tab = tab
    end

    def any? = @rows.any?

    def of(subject) = @rows[[ subject.class.polymorphic_name, subject.id ]]

    def other(subject)
      hold = of(subject)
      hold unless hold.nil? || mine?(hold)
    end

    def own_user?(hold) = @viewer.present? && hold.user_id == @viewer.id

    private

    def mine?(hold) = own_user?(hold) && @tab.present? && hold.tab == @tab
  end
end
