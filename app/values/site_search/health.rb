module SiteSearch
  # What a backend says of itself, for System status (spec §10): `status`
  # one of `STATUSES`, `detail` a plain sentence for a person or nil. It
  # holds no address and no credential.
  Health = Data.define(:status, :detail)

  class Health
    STATUSES = %i[ok warn failed].freeze

    def initialize(status:, detail: nil)
      raise ArgumentError, "a search backend's health is one of #{STATUSES.map(&:inspect).join(", ")}: #{status.inspect}" unless STATUSES.include?(status)

      super
    end
  end
end
