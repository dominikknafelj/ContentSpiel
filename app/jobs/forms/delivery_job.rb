module Forms
  # Delivers one submission to one destination (forms plan, decisions 6 and
  # 11): `Forms::DeliveryJob.perform_later(delivery)`, queued after the
  # commit of the send (`Forms::Submit`) or of a Send again
  # (`Forms::Resend`). Its one argument is the delivery, as its Global ID:
  # never an answer, a setting or a secret (the queue's row and Active Job's
  # log lines hold the arguments). The deliverer reads what it needs from
  # the rows, in the job.
  #
  # THE DELIVERER'S ANSWER (the contract of `Forms::DestinationTypes`):
  #   - nil: delivered. The delivery is recorded `sent`, and for a form that
  #     keeps nothing a submission whose every delivery is now sent is
  #     deleted (`Forms::DeleteSubmissions`, reason `delivered`). Each job
  #     reads the deliveries again after its own `sent` has committed (the
  #     job runs in no transaction), and nothing puts a sent delivery back to
  #     waiting (`Delivery#resend!` takes only a failed one), so of two
  #     deliveries finishing at once the later read sees both sent: one
  #     deletes, or both do and the second finds nothing and records
  #     nothing. None is left behind.
  #   - `Retry`: a failure worth another attempt (the mail's connection
  #     failure). Retried with backoff, `ATTEMPTS` in all; the deliverer is
  #     told which attempt is the last (`final_attempt:`), so it can record
  #     what it records once (the site's mail state) and answer `Failed`. A
  #     deliverer that still asks for a retry after the last is given up on
  #     (`gave_up`).
  #   - `Failed`: final. Recorded `failed` with its key and its line, the
  #     line scrubbed of every secret value of the destination (a server
  #     that echoes a key must not put it on a screen) and of every answer
  #     of the submission (a CRM that says "ada@example.com already exists"
  #     must not put a visitor's answer on a screen, a log or a span), and
  #     cut to `MailFailure::LINE_LIMIT` characters.
  #   - Anything else is a bug (a deliverer's own error, a template, answers
  #     the keys can no longer read): the delivery is recorded `failed` with
  #     the key `error` and no line, so it is listed as not delivered, can
  #     be sent again and is swept after `Forms::UNDELIVERED_DAYS` rather
  #     than waiting for ever, and the error is raised on, so the job fails
  #     as Active Job's jobs do. The site's mail state is not touched: an
  #     error that is no failed delivery blames no setting
  #     (`ApplicationMailer.deliver_in_job`).
  #
  # A delivery that is no longer `waiting` (sent by an earlier run, failed
  # and not sent again) is left alone. One whose destination was removed
  # from the form fails `no_destination`; one whose type is no longer
  # registered (a gem removed) `unknown_destination`. One whose submission
  # was deleted before the job ran (an editor, a purge) cannot be found:
  # the job is discarded with one line that names no address (pre-flight
  # ruling R9).
  #
  # Runs as the trusted nil actor on `:system`, like the trash's clean-up:
  # the deletion of a delivered submission reads "System" in the log.
  class DeliveryJob < ApplicationJob
    ATTEMPTS = 4
    ERROR = "error"

    queue_as :default

    discard_on ActiveJob::DeserializationError do |job, _error|
      job.logger.info "[ContentSpiel] A form's delivery was not sent: its submission was deleted before it went out."
    end

    retry_on DestinationTypes::Retry, attempts: ATTEMPTS, wait: :polynomially_longer do |job, _error|
      delivery = job.arguments.first
      delivery.record_failed!(key: "gave_up", line: nil, at: Time.current) if delivery.reload.waiting?
    end

    def perform(delivery)
      Current.set(actor: nil, channel: :system) { deliver(delivery) }
    end

    private

    def deliver(delivery)
      return unless delivery.waiting?

      destination = delivery.destination
      return delivery.record_failed!(key: "no_destination", line: nil, at: Time.current) unless destination

      type = destination.destination_type
      return delivery.record_failed!(key: "unknown_destination", line: nil, at: Time.current) unless type

      delivery.record_attempt!
      begin
        type.deliverer.deliver(delivery, final_attempt: executions >= ATTEMPTS)
      rescue DestinationTypes::Failed => failure
        return delivery.record_failed!(key: failure.key, line: scrubbed(failure.line, delivery, destination, type), at: Time.current)
      rescue DestinationTypes::Retry
        raise
      rescue StandardError
        delivery.record_failed!(key: ERROR, line: nil, at: Time.current)
        raise
      end

      delivery.record_sent!(at: Time.current)
      forget_delivered(delivery.submission)
    end

    # A submission a form that keeps nothing has delivered everywhere.
    def forget_delivered(submission)
      return if submission.form.keeps? || !submission.deliveries.reload.all?(&:sent?)

      result = DeleteSubmissions.call(submission.form, ids: [ submission.id ], reason: :delivered)
      logger.warn "[ContentSpiel] A delivered submission of form #{submission.form_id} was not deleted: #{result.errors.to_sentence}" unless result.ok?
    end

    # The line with every secret of the destination and every answer of the
    # submission (each non-blank value and display) replaced by "…", in any
    # case, the longest first, so an answer that holds another is not half
    # replaced. A secret or answers the keys can no longer read are ones the
    # deliverer could not have sent either.
    def scrubbed(line, delivery, destination, type)
      return nil if line.blank?

      secrets = type.secrets.filter_map do |name|
        destination.secret(name).presence
      rescue ActiveRecord::Encryption::Errors::Base
        nil
      end
      clean = (secrets + answer_texts(delivery)).uniq.sort_by { -it.length }.reduce(line.to_s) do |text, secret|
        text.gsub(Regexp.new(Regexp.escape(secret), Regexp::IGNORECASE), MailFailure::HIDDEN)
      end
      clean.lines.first.to_s.strip.truncate(MailFailure::LINE_LIMIT, omission: MailFailure::HIDDEN)
    end

    def answer_texts(delivery)
      Array(delivery.submission.answers).flat_map { |row| [ row["value"], row["display"] ] }
        .filter_map { |text| text.strip.presence if text.is_a?(String) }
    rescue ActiveRecord::Encryption::Errors::Base
      []
    end
  end
end
