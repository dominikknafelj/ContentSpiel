# One generation of an asset's widths: the fingerprint of the settings it was
# made with and, for each width made, the variation key (which builds its
# address) and the variation digest (which the cleanup and the 404 concern
# compare). Stored as JSON on `media_assets.renditions` under "current" and
# "previous"; this is the one reader of that shape.
module Media
  class Generation
    File = Data.define(:width, :key, :digest)

    def self.from(hash)
      return nil unless hash.respond_to?(:to_h) && hash.present?

      hash = hash.to_h.stringify_keys
      files = Array(hash["files"]).filter_map do |file|
        file = file.to_h.stringify_keys
        next if file["width"].blank? || file["key"].blank?

        File.new(width: file["width"].to_i, key: file["key"].to_s, digest: file["digest"].to_s)
      end
      new(fingerprint: hash["fingerprint"], files: files)
    end

    attr_reader :fingerprint, :files

    def initialize(fingerprint:, files:)
      @fingerprint = fingerprint
      @files = files.sort_by(&:width).freeze
    end

    def widths = files.map(&:width)

    def to_h
      { "fingerprint" => fingerprint, "files" => files.map { |f| { "width" => f.width, "key" => f.key, "digest" => f.digest } } }
    end
  end
end
