# A visitor's send of a form: one
# row per send, its `answers` ENCRYPTED with Active Record encryption
# (`Forms::Submission`), so the table holds no answer a database dump or a
# backup could read without the site's keys. Without keys no row is written
# at all (`Forms::Submit` answers UNAVAILABLE).
#
# Kept whatever the form says until every delivery has been sent; a form
# that keeps deletes it after its keeping time, one that does not as soon as
# it is delivered, or after `Forms::UNDELIVERED_DAYS` when it never was
# (`Forms::DeleteSubmissions`). The rows go with their form (cascade: a purge
# deletes them), and a page deleted for good leaves them with no page
# (nullify). No `updated_at`: a submission is never changed, only deleted.
class CreateFormSubmissions < ActiveRecord::Migration[8.1]
  def change
    create_table :form_submissions do |t|
      t.references :form, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :page, foreign_key: { on_delete: :nullify }
      t.string :locale, null: false
      t.text :answers, null: false
      t.datetime :created_at, null: false
      t.index %i[form_id created_at]
    end
  end
end
