module SiteSearch
  # What the boot does for search (spec §5.3, §6.6), from
  # config/initializers/site_search.rb's `after_initialize`: names the chosen
  # backend in the log, and in a process that serves requests enqueues
  # `SiteSearch::IndexCheckJob`, so nobody runs a task after an upgrade or a
  # change of `SEARCH_BACKEND`. A console, a rake task (`db:prepare`,
  # `assets:precompile`, `search:reindex` itself) and the test environment
  # enqueue nothing; every other boot counts as serving: the web server,
  # the queue's own process (`bin/jobs`), `bin/rails runner` and
  # `bin/rails generate`. Each of those enqueues one check, which writes
  # nothing, and the reindex job's limit and its state check make several
  # cost one build.
  #
  # A boot never fails because of search: a queue whose table is not there
  # yet is skipped, and an enqueue that raises (the queue's database
  # unreachable) is logged by its class alone, since a connection error's
  # message can hold the database's address.
  module BootCheck
    module_function

    def serving?(env: Rails.env, console: defined?(Rails::Console), rake: defined?(Rake.application) && Rake.application.top_level_tasks.any?)
      env.to_s != "test" && !console && !rake
    end

    def run(serving: serving?)
      return nil unless serving && queue_ready?

      IndexCheckJob.perform_later
      nil
    rescue StandardError => error
      Rails.logger.warn("[ContentSpiel] The search index was not checked at boot (#{error.class}); the next boot checks again.")
      nil
    end

    def log_line
      name = Backends.current_name
      "[ContentSpiel] Search: #{Backends.label(name)} (#{name})"
    end

    # Solid Queue's jobs table, when Solid Queue is the queue: a database
    # whose queue schema has not been loaded yet takes no job.
    def queue_ready?
      return true unless ActiveJob::Base.queue_adapter.is_a?(ActiveJob::QueueAdapters::SolidQueueAdapter)

      SolidQueue::Job.table_exists?
    end
  end
end
