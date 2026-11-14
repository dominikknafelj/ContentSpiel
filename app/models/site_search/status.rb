module SiteSearch
  # What System status's Search row says (spec §10), read once per request:
  #
  # - `state`: `:building` (the index is being built), `:stopped` (a build
  #   left `building` for over `IndexState::STALLED_AFTER` with no job at
  #   work), `:ready`, `:timeout` (the backend did not answer in `TIMEOUT`
  #   seconds, or raised) or `:unhealthy` (it answered `:warn` or `:failed`).
  # - `done`, `total`: the build's progress while `:building` or `:stopped`.
  # - `count`: the records the built-in finds (a page or a post counts once,
  #   whatever its languages); nil for an outside backend.
  # - `health`: the backend's own `SiteSearch::Health` while `:unhealthy`.
  #   Its `detail` is the one sentence of the backend contract, which holds
  #   no address and no credential; an error's message is never read here.
  # - `limited`: the switched-on languages of `Postgres::LIMITED`, for the
  #   built-in only (an outside engine has its own word handling).
  #
  # While a build runs the backend is not asked. Otherwise it is asked with a
  # `TIMEOUT` deadline, scrubbed (`Unavailable.scrubbing`: a failure is its
  # class alone), so System status waits for it no longer than that, and an
  # answer that comes after the deadline counts as none.
  Status = Data.define(:name, :label, :state, :done, :total, :count, :health, :limited)

  class Status
    TIMEOUT = 3

    # Whether a reindex job is waiting or running, so a build left `building`
    # is told from one still going. Where Solid Queue is not the queue, or
    # cannot be asked, no job is claimed to be running when it is not known:
    # the first is a build nothing will finish, the second says nothing.
    JOB_RUNNING = -> { reindex_job_running? }

    def self.reindex_job_running?
      return false unless ActiveJob::Base.queue_adapter.is_a?(ActiveJob::QueueAdapters::SolidQueueAdapter)

      SolidQueue::Job.where(class_name: SiteSearch::ReindexJob.name, finished_at: nil).exists?
    rescue StandardError
      true
    end

    def self.read(name: Backends.current_name, now: Time.current, job_running: JOB_RUNNING)
      label = Backends.label(name)
      limited = name == Backends::BUILT_IN ? Postgres::LIMITED & Locales.enabled : []
      row = IndexState.for(name)

      if row&.building?
        state = row.stopped?(now: now, job_running: job_running.call) ? :stopped : :building
        return new(name:, label:, state:, done: row.done, total: row.total, count: nil, health: nil, limited:)
      end

      asked(name:, label:, limited:, row:)
    end

    def self.asked(name:, label:, limited:, row:)
      backend = Backends.current
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      deadline = started + TIMEOUT
      health = Unavailable.scrubbing(backend: name) { backend.health(deadline: deadline) }
      count = Unavailable.scrubbing(backend: name) { backend.entry_count } if name == Backends::BUILT_IN && health.status == :ok
      late = Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      done, total = row&.done, row&.total
      return new(name:, label:, state: :timeout, done:, total:, count: nil, health: nil, limited:) if late
      return new(name:, label:, state: :unhealthy, done:, total:, count: nil, health: health, limited:) unless health.status == :ok

      new(name:, label:, state: :ready, done:, total:, count:, health: nil, limited:)
    rescue Unavailable
      new(name:, label:, state: :timeout, done: nil, total: nil, count: nil, health: nil, limited:)
    end
    private_class_method :asked
  end
end
