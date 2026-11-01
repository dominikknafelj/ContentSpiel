module Media
  # Whether a Regenerate is running, for the Images card's "Regenerating: 5 of
  # 12". Nothing records a run: `Media::Regenerate` queues plain jobs and
  # keeps no batch, and the card has no live refresh. So a run is inferred
  # from what is already kept, and is on only while ALL of these hold:
  #
  # - the newest `media.regenerated` event (the audit log's record of a press)
  #   queued something (its `count` is above zero) and is under `MAX_AGE` old;
  # - no `settings.updated` event after it changed an `image_*` setting: images
  #   outstanding because the settings moved on were never pressed, and the
  #   backfill does not remake them;
  # - some image that existed at the press (`created_at` at or before it) is
  #   still outstanding: kept, not made with the saved settings and not
  #   failed (a failed image is not being made and waits for the next press).
  #   An upload after the press never counts: it has its own job.
  #
  # The line is "done of N": N is the press's own count and `done` is N less
  # what is outstanding, never below 0. As of the page's load; nothing polls.
  #
  # The remaining limit: this is an inference, not a record. Within 24 hours
  # of a press, an image of the press whose job died without recording a
  # failure (a lost worker) still reads as outstanding, so the line stays up
  # until the day is over or the image settings change; and an image that was
  # outstanding for another reason (an upload's own job not yet run, made
  # before the press) is counted as part of the run. Exact would need a stored
  # run.
  class RegenerationRun
    MAX_AGE = 24.hours

    def initialize(fingerprint: ImageSettings.current.fingerprint, scope: Media::Asset.kept, now: Time.current)
      @fingerprint = fingerprint
      @scope = scope
      @now = now
    end

    # `{ done:, of: }`, or nil when nothing says a run is on.
    def current
      press = Audit::Event.where(action: "media.regenerated").order(occurred_at: :desc).first
      queued = press&.metadata&.dig("count").to_i
      return nil unless queued.positive?
      return nil if press.occurred_at < @now - MAX_AGE
      return nil if image_settings_changed_since?(press.occurred_at)

      outstanding = outstanding_at(press.occurred_at)
      return nil unless outstanding.positive?

      { done: [ queued - outstanding, 0 ].max, of: queued }
    end

    private

    def outstanding_at(time)
      table = Media::Asset.arel_table
      @scope.where(table[:created_at].lteq(time))
        .where(table[:renditions_fingerprint].is_distinct_from(@fingerprint))
        .where(renditions_failed_at: nil).count
    end

    def image_settings_changed_since?(time)
      Audit::Event.where(action: "settings.updated").where(Audit::Event.arel_table[:occurred_at].gt(time))
        .pluck(:field_changes).any? { |changes| changes.keys.any? { |name| name.start_with?("image_") } }
    end
  end
end
