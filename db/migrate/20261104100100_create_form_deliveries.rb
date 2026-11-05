# One destination's delivery of one submission: its
# state (`waiting`, `sent`, `failed`), its attempts and, for a failure, the
# deliverer's key and the other side's line with every secret scrubbed out
# (`Forms::DeliveryJob`). Written by the job, not a service: a delivery's
# state is a job's, as mail's state columns are (`Forms::Delivery`).
#
# `kind` is the destination's kind when the delivery was made, so a delivery
# whose destination was removed from the form since (nullify) still says
# where it was meant to go. `queued_fingerprint` is the mail settings'
# fingerprint when it was queued (an HMAC, `MailSettings#fingerprint`): a
# mail sent under it verifies the settings only while it is still the
# current one, as `ApplicationMailer.queue` has it.
class CreateFormDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :form_deliveries do |t|
      t.references :submission, null: false, foreign_key: { to_table: :form_submissions, on_delete: :cascade }
      t.references :destination, foreign_key: { to_table: :form_destinations, on_delete: :nullify }
      t.string :kind, null: false
      t.string :state, null: false, default: "waiting"
      t.integer :attempts, null: false, default: 0
      t.jsonb :failure
      t.string :queued_fingerprint
      t.datetime :sent_at
      t.datetime :failed_at
      t.timestamps
      t.index :state
      t.check_constraint "state::text = ANY (ARRAY['waiting'::text, 'sent'::text, 'failed'::text])", name: "form_deliveries_state_known"
    end
  end
end
