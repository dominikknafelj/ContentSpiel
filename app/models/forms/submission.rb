module Forms
  # A visitor's send of a form: when, in which language, from which page, and the answers.
  #
  # THE ANSWERS ARE ENCRYPTED at rest (`encrypts :answers`, Active Record
  # encryption with the site's keys), as JSON: the stored shape of
  # `Forms::Answers` (`[{ "key", "type", "label", "value", "display" }]`),
  # whose labels and displays are the default language's as the form said
  # them at the send, so an edit of the form changes no old submission
  # Nothing else holds an answer: not the audit log (its
  # events name the submission by id), not a job's arguments (a delivery's
  # Global ID), not a log line, not a URL. Without encryption keys no
  # submission is written at all (`Forms::Submit` answers UNAVAILABLE).
  #
  # A submission is a row whatever the form keeps: a form that keeps nothing
  # loses it once every delivery has been sent (`Forms::DeliveryJob`), or
  # after `Forms::UNDELIVERED_DAYS` when one never was; one that keeps, after
  # its keeping time. Every deletion is `Forms::DeleteSubmissions`; the rows
  # also go with their form (the foreign key cascades) and their deliveries
  # with them. Never changed after it is written (no `updated_at`).
  #
  # Keys that changed or went since a submission was written make its
  # answers unreadable: `#readable?` says so without raising, so a list
  # can say "Can't be read" and still offer Delete.
  class Submission < ApplicationRecord
    self.table_name = "form_submissions"

    # No `type: Array`: Active Record stores the type's default (an empty
    # list) as NULL, and a submission of a form with no fields is still one.
    serialize :answers, coder: JSON
    encrypts :answers

    belongs_to :form, class_name: "Forms::Form", inverse_of: :submissions
    belongs_to :page, optional: true
    has_many :deliveries, class_name: "Forms::Delivery", inverse_of: :submission

    validates :locale, presence: true

    # Whether the answers can be decrypted with the keys the site has now.
    def readable?
      answers
      true
    rescue ActiveRecord::Encryption::Errors::Base
      false
    end

    # Every delivery has been sent (true for a submission with none: it has
    # nothing left to go anywhere).
    def delivered? = deliveries.all?(&:sent?)

    # A delivery failed: listed as "Not delivered", with Send again.
    def undelivered? = deliveries.any?(&:failed?)
  end
end
