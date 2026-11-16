module Publishing
  # A record's published versions as a paged list, newest first, for the
  # History screen. The list reads the copies WITHOUT their content
  # (`snapshot`, `blocks`: most of a copy's weight) and their publishers in
  # one more statement; `find` and `previous` read a whole copy, for the
  # screen that compares two.
  #
  # WHICH COPY IS IN FORCE follows the order of copies (`Publishing::Version`):
  # the newest not after `now`. Whether that means "on the site" depends on
  # the record, since a scheduled record's first copy is in force at once and
  # hidden by `published_at`: such a copy is `:scheduled`, like the pending
  # one (a change waiting for its time). A draft shows nothing, so all its
  # copies are `:earlier`.
  class History
    PER_PAGE = 50
    COLUMNS = %w[id record_type record_id number live_at created_at created_by_id].freeze

    # `publisher` is nil for a copy kept when history began.
    # `was_scheduled`: the copy was taken for a later time (a scheduled change).
    Row = Data.define(:version, :number, :live_at, :publisher, :state, :was_scheduled)
    # `changes`: the mark is set. `same_as`: the number of the copy in force
    # when the rows differ from the newest copy in nothing, else nil.
    # `saved_at`: when the rows were last saved.
    Working = Data.define(:changes, :same_as, :saved_at)

    attr_reader :record, :now

    def initialize(record, page: 1, now: Time.current)
      @record = record
      @now = now
      @page = page
    end

    def pagination
      @pagination ||= Pagination.new(page: @page, per_page: PER_PAGE, total: copies.count)
    end

    def rows
      @rows ||= begin
        return [] if pagination.out_of_range?

        in_force = Publishing.current(record, now: now)&.id
        copies.select(*COLUMNS).includes(:created_by).order(number: :desc).limit(PER_PAGE).offset(pagination.offset).map do |version|
          Row.new(version: version, number: version.number, live_at: version.live_at, publisher: version.created_by,
            state: state_of(version, in_force), was_scheduled: version.live_at > version.created_at)
        end
      end
    end

    def working
      @working ||= Working.new(changes: record.unpublished_changes_at.present?, saved_at: record.updated_at,
        same_as: (Publishing.current(record, now: now)&.number if Changes.of(record).none?))
    end

    def find(number) = copies.find_by!(number: number)

    # The newest copy, pending or not: the version the screen shows first.
    # Nil for a record never published.
    def newest = copies.order(number: :desc).first

    # Every copy's number, newest first: what a version can be compared with.
    def numbers = copies.order(number: :desc).pluck(:number)

    # The copy before `number`, or nil for the first.
    def previous(number) = copies.where(arel_table[:number].lt(number)).order(number: :desc).first

    private

    def copies = Version.of(record)

    def arel_table = Version.arel_table

    def state_of(version, in_force)
      return :scheduled if version.live_at > now
      return :earlier unless version.id == in_force

      record.published_at.nil? ? :earlier : (record.published_at <= now ? :on_site : :scheduled)
    end
  end
end
