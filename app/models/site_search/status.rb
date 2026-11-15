module SiteSearch
  # What System status's Search row says (spec §10), read once per request:
  #
  # - `state`: `:building` (the index is being built), `:stopped` (a build
  #   left `building` for over `IndexState::STALLED_AFTER` with no job at
  #   work), `:not_built` (no row and no reindex job waiting or running: a job
  #   queued with no row yet reads `:building`), `:out_of_date` (a ready row whose
  #   fingerprint no longer matches, with no job at work), `:ready`,
  #   `:timeout` (the backend did not answer in `TIMEOUT` seconds, or raised)
  #   or `:unhealthy` (it answered `:warn` or `:failed`).
  # - `done`, `total`: the build's progress while `:building` or `:stopped`.
  # - `count`: the records the built-in finds (a page or a post counts once,
  #   whatever its languages); nil for an outside backend.
  # - `health`: the backend's own `SiteSearch::Health` once it answered
  #   (`:ready` or `:unhealthy`).
  #   Its `detail` is the one sentence of the backend contract, which holds
  #   no address and no credential; an error's message is never read here.
  # - `limited`: the switched-on languages of `Postgres::LIMITED`, which the
  #   built-in searches by the text a page contains, with no stemming and no
  #   correction; for the built-in only (an outside engine has its own word
  #   handling).
  # - `tags_only`: whether the backend answers no `suggest`
  #   (`Backend::OPTIONAL_METHODS`), so the suggestions while typing offer
  #   tags alone; never for the built-in.
  #
  # While a build runs the backend is not asked. Otherwise `health` runs in a
  # thread that is waited for `TIMEOUT` seconds and no longer, scrubbed
  # (`Unavailable.scrubbing`: a failure is its class alone), so a backend that
  # ignores its deadline holds neither System status nor the wizard; an answer
  # that did not come in time counts as none.
  Status = Data.define(:name, :label, :state, :done, :total, :count, :health, :limited, :tags_only)

  class Status
    TIMEOUT = 3

    # Whether a reindex job is waiting or running, so a build left `building`
    # is told from one still going. A job that failed keeps no `finished_at`
    # but has a failed execution: it is not running. Where Solid Queue is not
    # the queue no job is claimed; where it cannot be asked, one is, so the
    # row never says "stopped" on a guess.
    JOB_RUNNING = -> { reindex_job_running? }

    def self.reindex_job_running?
      return false unless ActiveJob::Base.queue_adapter.is_a?(ActiveJob::QueueAdapters::SolidQueueAdapter)

      SolidQueue::Job.where(class_name: SiteSearch::ReindexJob.name, finished_at: nil)
        .where.not(id: SolidQueue::FailedExecution.select(:job_id)).exists?
    rescue StandardError
      true
    end

    def self.read(now: Time.current, job_running: JOB_RUNNING, timeout: TIMEOUT)
      name = Backends.current_name
      label = Backends.label(name)
      limited = name == Backends::BUILT_IN ? Postgres::LIMITED & Locales.enabled : []
      row = IndexState.for(name)
      facts = { name:, label:, limited:, tags_only: tags_only?(name) }

      if row&.building?
        state = row.stopped?(now: now, job_running: job_running.call) ? :stopped : :building
        return new(**facts, state:, done: row.done, total: row.total, count: nil, health: nil)
      end
      if row.nil?
        return new(**facts, state: :not_built, done: nil, total: nil, count: nil, health: nil) unless job_running.call

        return new(**facts, state: :building, done: 0, total: 0, count: nil, health: nil)
      end
      if IndexState.empty_or_stale?(name) && !job_running.call
        return new(**facts, state: :out_of_date, done: row.done, total: row.total, count: nil, health: nil)
      end

      asked(**facts, row:, timeout:)
    end

    # Asks the object only whether it has the method, never the engine. A
    # backend that cannot be built answers false here, and the row shows the
    # failure only where the backend is asked: `:timeout` once its index row
    # is ready. While the row reads `:building`, `:stopped`, `:not_built` or
    # `:out_of_date` the backend is not asked, so nothing on the row says it
    # cannot be built.
    def self.tags_only?(name)
      name != Backends::BUILT_IN && !Backends.current.respond_to?(:suggest)
    rescue StandardError
      false
    end

    # The thread is abandoned when it does not answer in time, never killed: a
    # killed thread can leave a client's connection half used. It ends when
    # the backend's own call does, so while a backend hangs every visit of
    # System status (or the wizard's check) leaves one thread behind: the leak
    # is bounded by how often those pages are opened, and accepted.
    def self.asked(name:, label:, limited:, tags_only:, row:, timeout:)
      backend = Backends.current
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      answer = {}
      thread = Thread.new do
        Rails.application.executor.wrap do
          answer[:health] = Unavailable.scrubbing(backend: name) { backend.health(deadline: deadline) }
        end
      rescue StandardError
        answer[:failed] = true
      end
      thread.report_on_exception = false
      facts = { name:, label:, limited:, tags_only:, done: row&.done, total: row&.total, count: nil, health: nil }
      return new(**facts, state: :timeout) unless thread.join(timeout) && answer[:health]

      health = answer[:health]
      return new(**facts, state: :unhealthy, health: health) unless health.status == :ok

      count = Unavailable.scrubbing(backend: name) { backend.entry_count } if name == Backends::BUILT_IN
      new(**facts, state: :ready, count: count, health: health)
    rescue Unavailable
      new(name:, label:, state: :timeout, done: nil, total: nil, count: nil, health: nil, limited:, tags_only:)
    end
    private_class_method :tags_only?, :asked
  end
end
