module Publishing
  # A record could not be given, or keep, the address it wants because
  # another record holds it. RAISED for the record's own address only, by
  # `Publishing.keep_address!`, and rescued by the service that saves or
  # publishes the record, whose transaction is rolled back with everything in
  # it. REPORTED, never raised, for a live record that lost its address to
  # somebody else's write or to the clock (`PublicSite::Paths.report_clash`).
  #
  # `lost` is data, not wording: the `PublicSite::Paths::Change`s that had to
  # yield, each with its `record`, the `locale` and the address it wanted
  # (`to`). A screen words them.
  class AddressTaken < StandardError
    attr_reader :lost

    def initialize(lost)
      @lost = lost
      super("#{lost.map(&:record).uniq.size} record(s) without the address they want: another record holds it")
    end
  end
end
