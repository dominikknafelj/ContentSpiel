module Forms
  # One destination's delivery of one submission (forms plan, decisions 1
  # and 6): `waiting` until `Forms::DeliveryJob` has delivered it (`sent`)
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
  # the current one, as a mail queued through `ApplicationMailer.queue` does
  # (pre-flight ruling R9).
  class Delivery < ApplicationRecord
    self.table_name = "form_deliveries"

    STATES = %w[waiting sent failed].freeze

    belongs_to :submission, class_name: "Forms::Submission", inverse_of: :deliveries
    belongs_to :destination, class_name: "Forms::Destination", optional: true

    validates :kind, presence: true
    validates :state, inclusion: { in: STATES }

    before_create { self.queued_fingerprint ||= MailSettings.current.fingerprint }

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

    # Back to waiting, to be queued again (`Forms::Resend`), under the mail
    # settings as they are now.
    def resend!
      update_columns(state: "waiting", failure: nil, failed_at: nil, attempts: 0, # version: none (a delivery's state is not content)
        queued_fingerprint: MailSettings.current.fingerprint, updated_at: Time.current)
    end
  end
end
