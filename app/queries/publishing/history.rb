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
    COLUMNS = %w[id record_type record_id number live_at created_at created_by_id kept_when_history_began].freeze

    # `at`: when the copy goes or went live for a visitor (`shown_at`).
    # `publisher` is the person who published it, nil but for `:person`.
    # `credit` is who the row names (`credit_of`): `:person`, `:removed`,
    # `:system` or `:kept`. `was_scheduled`: the copy went live later than it
    # was taken: a scheduled change, or a scheduled record's copy in force.
    Row = Data.define(:version, :number, :at, :publisher, :credit, :state, :was_scheduled)
    # `changes`: the mark is set. `saved_at`: when the rows were last saved.
    Working = Data.define(:changes, :saved_at)

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

        copies.select(*COLUMNS).includes(:created_by).order(number: :desc).limit(PER_PAGE).offset(pagination.offset).map do |version|
          Row.new(version: version, number: version.number, at: shown_at(version), publisher: version.created_by,
            credit: credit_of(version), state: state_of(version), was_scheduled: was_scheduled?(version))
        end
      end
    end

    def working
      @working ||= Working.new(changes: record.unpublished_changes_at.present?, saved_at: record.updated_at)
    end

    # WHEN A COPY GOES OR WENT LIVE FOR A VISITOR, which is not always its
    # `live_at`: a scheduled record's first copy is in force from the moment
    # it is taken and hidden until `published_at`, the one clock of a
    # record's visibility (`docs/reference/publishing.md`, "The order of
    # copies"). So the copy in force of a record with a time shows from the
    # later of the two (and moves with "Edit schedule"); any other copy at
    # its own `live_at`. The row's time, the versions' summary and the
    # restore dialog's sentence all read it here.
    def shown_at(version)
      return version.live_at unless timed_in_force?(version)

      [ version.live_at, record.published_at ].max
    end

    def find(number) = copies.find_by!(number: number)

    # The newest copy, pending or not: the version the screen shows first.
    # Nil for a record never published.
    def newest = copies.order(number: :desc).first

    # Every copy's number, newest first: what a version can be compared with.
    def numbers = copies.order(number: :desc).pluck(:number)

    # The copy before `number`, or nil for the first.
    def previous(number) = copies.where(arel_table[:number].lt(number)).order(number: :desc).first

    # WHO A COPY IS CREDITED TO (the StudioHistory card, "A version row"):
    # `:person` when its publisher's account exists; `:removed` when an id
    # was recorded and its user is gone (the id outlives the account:
    # `KeepVersionPublishers`); `:kept` for a copy the migration made of what
    # was live when history began (`kept_when_history_began`, and nothing
    # else: a later copy with no publisher is never that, whatever its date);
    # `:system` for any other copy nobody was behind (the console, a seed,
    # `bin/load`). A scheduled change is credited to whoever scheduled it,
    # since the copy is taken when it is scheduled (`take!`'s `by:`),
    # and comes into force with no write when its time passes.
    def self.credit_of(version)
      return :person if version.created_by
      return :removed if version.created_by_id
      return :kept if version.kept_when_history_began

      :system
    end

    private

    def credit_of(version) = self.class.credit_of(version)

    def copies = Version.of(record)

    def arel_table = Version.arel_table

    def in_force_id = defined?(@in_force_id) ? @in_force_id : (@in_force_id = Publishing.current(record, now: now)&.id)

    def publishing_state = @publishing_state ||= State.of(record, now: now)

    def timed_in_force?(version) = version.id == in_force_id && publishing_state.timed?

    # A copy taken for a later time (a scheduled change), or the copy in
    # force of a record whose time came after the copy was taken.
    def was_scheduled?(version)
      version.live_at > version.created_at || (timed_in_force?(version) && record.published_at > version.live_at)
    end

    def state_of(version)
      return :scheduled if version.live_at > now
      return :earlier unless timed_in_force?(version)

      publishing_state.scheduled? ? :scheduled : :on_site
    end
  end
end
