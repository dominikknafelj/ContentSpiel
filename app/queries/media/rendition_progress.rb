module Media
  # How far the library is from the current image settings, for Settings →
  # Images: of the images in `scope`, how many there are, how many were made
  # with the settings whose `fingerprint` is given (the recorded generation's
  # fingerprint equals it) and how many have failed (a failure recorded, and
  # not made with these settings: an image made since its failure is made).
  #
  # One statement however large the library is. The caller narrows `scope`
  # (the kept images; a trashed image is in no count), as it narrows any list.
  class RenditionProgress
    def initialize(fingerprint: ImageSettings.current.fingerprint, scope: Media::Asset.kept)
      @fingerprint = fingerprint
      @scope = scope
    end

    def counts
      table = Media::Asset.arel_table
      made = table[:renditions_fingerprint].eq(@fingerprint)
      failed = table[:renditions_failed_at].not_eq(nil).and(table[:renditions_fingerprint].is_distinct_from(@fingerprint))
      total, made_count, failed_count = @scope.pick(Arel.star.count, SqlNodes.count_where(made), SqlNodes.count_where(failed))
      { total: total, made: made_count, failed: failed_count }
    end
  end
end
