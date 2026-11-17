# The digest's own retries after a failed send (docs/reference/alerting.md,
# "The digest"): how many sends of an alert's digest failed in a row and
# when the last one did, which together say when the next try is due. A
# successful send puts both back. Kept on the alerts the digest carried, so
# a new alert starts with none and the rows that waited keep theirs.
class AddDigestRetryToAlerts < ActiveRecord::Migration[8.1]
  def change
    add_column :alerts, :digest_failures, :integer, null: false, default: 0
    add_column :alerts, :digest_failed_at, :datetime
  end
end
