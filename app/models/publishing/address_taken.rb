module Publishing
  # A published copy would leave a live record without an address: raised by
  # `take!` of `Publishing::Version`, the one place that asks, and rescued by the
  # service that called it, whose transaction is rolled back with everything
  # in it. Also what the clock's own clash is reported as, never raised
  # (`PublicSite::Paths.report_clash`).
  #
  # `lost` is data, not wording: the `PublicSite::Paths::Change`s that had to
  # yield, each with its `record`, the `locale` and the address it wanted
  # (`to`). A screen words them.
  class AddressTaken < StandardError
    attr_reader :lost

    def initialize(lost)
      @lost = lost
      super("a published copy would leave #{lost.map(&:record).uniq.size} live record(s) without an address")
    end
  end
end
