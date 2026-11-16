# GET /ready: whether this process can reach its databases, for an uptime
# monitor or a load balancer that asks more than `/up` ("the app booted").
# Beside `/up`, outside both host constraints and exempt from host
# authorization, the SSL redirect and the setup redirect (`HostSettings::HEALTH_CHECK`),
# since a monitor asks it by IP over plain HTTP.
#
# An answer of two words and a status, nothing else: no exception message, no
# database or host name, no cookie, nothing a cache may keep. A probe that
# raises is a 503, never a 500, and the log line names the exception's class
# only (a driver's message can hold a connection string).
class ReadinessController < ActionController::API
  # Each probe is a callable that raises when what it checks is not reachable;
  # nil means the defaults. A test swaps the list, as `Setup::SystemCheck`'s
  # probes are swapped.
  class_attribute :probes, instance_accessor: false, default: nil

  def self.default_probes
    probes = [ -> { check(ActiveRecord::Base) } ]
    probes << -> { check(SolidQueue::Record) } if solid_queue?
    probes
  end

  def self.solid_queue?
    ActiveJob::Base.queue_adapter.class.name == "ActiveJob::QueueAdapters::SolidQueueAdapter"
  end

  def self.check(record_class)
    record_class.with_connection { |connection| connection.select_value("SELECT 1") } # sql: the cheapest round trip that proves the connection answers
  end

  def show
    response.headers["Cache-Control"] = "no-store"
    (self.class.probes || self.class.default_probes).each(&:call)
    render plain: "ok"
  rescue StandardError => error
    Rails.logger.warn("[ContentSpiel] Readiness check failed: #{error.class.name}")
    render plain: "unavailable", status: :service_unavailable
  end
end
