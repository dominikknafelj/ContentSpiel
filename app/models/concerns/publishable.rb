# `published_at` doubles as draft/schedule flag (spec §10.4): nil is a draft,
# a future time is scheduled, now or past is live. The `published` scope is
# what the public site serves; a beginless range compiles to
# `published_at <= now()`, which drops both NULLs and future dates.
module Publishable
  extend ActiveSupport::Concern

  STATUSES = %w[draft scheduled live].freeze

  included do
    scope :published, -> { where(published_at: ..Time.current) }
  end

  def status
    if published_at.nil?
      "draft"
    elsif published_at > Time.current
      "scheduled"
    else
      "live"
    end
  end

  def live?
    status == "live"
  end

  def publish_now!
    update!(published_at: Time.current)
  end

  def unpublish!
    update!(published_at: nil)
  end
end
