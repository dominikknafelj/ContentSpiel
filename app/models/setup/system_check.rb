# Read-only environment checks shown in the setup wizard and on CS Studio's
# System status page (design spec 2026-09-26 §4). Never blocking: every
# failure is a warning explaining what won't work and how to fix it. Each
# probe is a callable so tests can swap it; a probe that raises (including
# LoadError, which is what a missing libvips looks like) counts as a
# failure.
module Setup
  class SystemCheck
    Result = Data.define(:label, :status, :message) do
      def ok? = status == :ok
    end

    # Talks to the storage service directly rather than through
    # ActiveStorage::Blob.create_and_upload!, which saves the blob row before
    # uploading -- if the upload fails (the case this probe exists to catch),
    # the row would be orphaned since there'd be nothing left to purge it.
    STORAGE_PROBE = -> {
      payload = "contentspiel system check"
      key = "system-check-#{SecureRandom.hex(8)}"
      service = ActiveStorage::Blob.service
      service.upload(key, StringIO.new(payload))
      begin
        service.download(key) == payload
      ensure
        service.delete(key)
      end
    }

    IMAGE_PROBE = -> {
      require "vips"
      Vips::Image.black(4, 4).resize(0.5).write_to_buffer(".png").bytesize.positive?
    }

    WORKER_ALIVE_PROBE = -> { SolidQueue::Process.where(last_heartbeat_at: 5.minutes.ago..).exists? }

    def self.run(**options) = new(**options).run

    def initialize(storage_probe: STORAGE_PROBE, image_probe: IMAGE_PROBE, worker_alive_probe: WORKER_ALIVE_PROBE,
      queue_adapter: ActiveJob::Base.queue_adapter_name,
      mail_delivery_method: ActionMailer::Base.delivery_method,
      mail_smtp_address: ActionMailer::Base.smtp_settings[:address],
      mail_host: ActionMailer::Base.default_url_options[:host])
      @storage_probe = storage_probe
      @image_probe = image_probe
      @worker_alive_probe = worker_alive_probe
      @queue_adapter = queue_adapter.to_s
      @mail_delivery_method = mail_delivery_method.to_s
      @mail_smtp_address = mail_smtp_address.to_s
      @mail_host = mail_host.to_s
    end

    def run
      [ storage, image_processing, background_jobs, mail ]
    end

    private
      def storage
        if probe(@storage_probe)
          ok("File storage", "Uploads can be stored and read back.")
        else
          warning("File storage", "Uploads can't be stored, so logos and images will fail. " \
            "Check that the storage directory (storage/ by default) is writable and on a persistent volume.")
        end
      end

      def image_processing
        if probe(@image_probe)
          ok("Image processing", "Images can be resized.")
        else
          warning("Image processing", "Images can't be resized, so image variants and logo resizing will fail. " \
            "Install libvips on the server.")
        end
      end

      def background_jobs
        if @queue_adapter != "solid_queue"
          ok("Background jobs", "Jobs run inside the web process (#{@queue_adapter} adapter).")
        elsif probe(@worker_alive_probe)
          ok("Background jobs", "A Solid Queue worker is running.")
        else
          warning("Background jobs", "No Solid Queue worker has checked in recently, so queued work " \
            "(upload analysis, emails) won't run. Set SOLID_QUEUE_IN_PUMA=1 or run bin/jobs.")
        end
      end

      def mail
        configured = @mail_delivery_method == "smtp" &&
          @mail_smtp_address.present? && @mail_smtp_address != "localhost" &&
          @mail_host.present? && @mail_host != "example.com"

        if configured
          ok("Outgoing mail", "Outgoing mail is configured.")
        else
          warning("Outgoing mail", "Password reset by email isn't configured. To reset a password without email, " \
            "run bin/rails console and User.find_by(email_address: \"you@example.com\").update!(password: \"new password\").")
        end
      end

      def probe(callable)
        callable.call
      rescue StandardError, LoadError
        false
      end

      def ok(label, message) = Result.new(label:, status: :ok, message:)
      def warning(label, message) = Result.new(label:, status: :warning, message:)
  end
end
