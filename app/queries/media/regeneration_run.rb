module Media
  # Whether a Regenerate is running, for the Images card's "Regenerating: 5 of
  # 12". Nothing records a run: `Media::Regenerate` queues plain jobs and
  # keeps no batch, and the card has no live refresh. So a run is inferred
  # from what is already kept, and is on while ALL of these hold:
  #
  # - the newest `media.regenerated` event (the audit log's record of a press)
  #   queued something (its `count` is above zero);
  # - no `settings.updated` event after it changed an `image_*` setting: images
  #   outstanding because the settings moved on were never pressed, and the
  #   backfill does not remake them;
  # - images are outstanding now: not made with the saved settings and not
  #   failed (a failed image is not being made, and waits for the next press).
  #
  # The line is "done of N": N is the press's count (the images uploaded since
  # raise it to what is outstanding, so `done` is never negative) and `done` is
  # N less what is outstanding. As of the page's load; nothing here polls.
  # One statement for the press, one for the later settings saves, and the
  # progress counts the caller already has.
  class RegenerationRun
    def initialize(progress:)
      @progress = progress
    end

    # `{ done:, of: }`, or nil when nothing says a run is on.
    def current
      outstanding = @progress[:total] - @progress[:made] - @progress[:failed]
      return nil unless outstanding.positive?

      press = Audit::Event.where(action: "media.regenerated").order(occurred_at: :desc).first
      queued = press&.metadata&.dig("count").to_i
      return nil unless queued.positive?
      return nil if image_settings_changed_since?(press.occurred_at)

      total = [ queued, outstanding ].max
      { done: total - outstanding, of: total }
    end

    private

    def image_settings_changed_since?(time)
      Audit::Event.where(action: "settings.updated").where(Audit::Event.arel_table[:occurred_at].gt(time))
        .pluck(:field_changes).any? { |changes| changes.keys.any? { |name| name.start_with?("image_") } }
    end
  end
end
