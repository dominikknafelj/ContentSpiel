module Forms
  # One destination's delivery of one submission: `waiting` until `Forms::DeliveryJob` has delivered it (`sent`)
  # or given up (`failed`, with the deliverer's `key` and the other side's
  # `line`, scrubbed of every secret of the destination by the job).
  #
  # NOT A SERVICE'S WRITE. A delivery's state is a job's, as mail's state
  # columns are (`MailSettings.record_success!`): nobody asks for it, it is
  # no content and no setting, and auditing every attempt would bury the
  # log. Each writer below is one `update_columns`, with no callback, saying
  # `# version: none` on its line (test/lib/version_bump_test.rb); what an
  # editor asks for (sending a failed one again, deleting) is a service
  # that audits (`Forms::Resend`, `Forms::DeleteSubmissions`).
  #
  # `kind` is the destination's kind when the delivery was made, kept for a
  # destination removed from the form since (`destination` is then nil).
  # `queued_fingerprint` is the mail settings' fingerprint when it was
  # queued (an HMAC that holds no setting, `MailSettings#fingerprint`): the
  # mail destination's send verifies the settings only while it is still
  # the current one, as a mail queued through `ApplicationMailer.queue` does.
  class Delivery < ApplicationRecord
    self.table_name = "form_deliveries"

    STATES = %w[waiting sent failed].freeze

    belongs_to :submission, class_name: "Forms::Submission", inverse_of: :deliveries
    belongs_to :destination, class_name: "Forms::Destination", optional: true

    validates :kind, presence: true
    validates :state, inclusion: { in: STATES }

    before_create { self.queued_fingerprint ||= MailSettings.current.fingerprint }

    # The mail deliveries that failed because mail was not set up
    # (`Destinations::Mail::NOT_READY`) and are still failed: what is sent
    # again once it is (`Forms::ResendNotReadyJob`), and what the clean-up
    # spares while it is not (`Forms::PurgeExpiredJob`).
    scope :waiting_for_mail, -> {
      where(state: "failed", kind: Destinations::Mail::KIND)
        .where(SqlNodes.json_text(arel_table[:failure], "key").eq(Destinations::Mail::NOT_READY))
    }

    STATES.each { |name| define_method(:"#{name}?") { state == name } }

    def record_attempt!
      update_columns(attempts: attempts + 1, updated_at: Time.current) # version: none (a delivery's state is not content)
    end

    def record_sent!(at:)
      update_columns(state: "sent", sent_at: at, failure: nil, updated_at: at) # version: none (a delivery's state is not content)
    end

    # `key` a short word the screens put into words, `line` the other side's
    # answer, already scrubbed of secrets, or nil.
    def record_failed!(key:, line:, at:)
      update_columns(state: "failed", failure: { "key" => key.to_s, "line" => line }, failed_at: at, updated_at: at) # version: none (a delivery's state is not content)
    end

    # A FAILED delivery back to waiting, to be queued again (`Forms::Resend`),
    # under the mail settings as they are now; answers whether it was. Only a
    # failed one, decided in the statement itself (`state = 'failed'`), so a
    # sent delivery is never put back: a job that has just sent its
    # delivery can trust that it stays sent (`Forms::DeliveryJob`).
    def resend!
      now = Time.current
      columns = { state: "waiting", failure: nil, failed_at: nil, attempts: 0, queued_fingerprint: MailSettings.current.fingerprint, updated_at: now }
      changed = self.class.where(id: id, state: "failed").update_all(columns) == 1 # version: none (a delivery's state is not content)
      reload if changed
      changed
    end
  end
end
