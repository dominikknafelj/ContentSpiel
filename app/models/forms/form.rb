module Forms
  # A form a visitor fills in (forms spec, "The form"; plan decisions 1, 3,
  # 13): its own record, reusable on many pages through a Form block, with
  # its submissions in one place. `Forms::Form`, not `Form`, so the block
  # type `form` stays a name the generator takes (`BlockTypes::Form` would
  # shadow a top-level `Form`), as the library image is `Media::Asset`.
  #
  # NO DRAFTS. A change is live at its Save, an explicit one (`Forms::Save`),
  # never autosave, so a half-typed field is never live: that is what drafts
  # would have given a form. Every write that changes what a placed form
  # draws moves the public content version (decision 9): a form has no
  # published copy, so its rows are what the site shows. The services that
  # write it call `PublicSite.bump_version!` themselves; this model has no
  # callback that does.
  #
  # TRASHABLE, as a post is (`Trashable`, `Trash::Move`/`Restore`/`Purge`).
  # A trashed form draws nothing and its endpoint answers "no longer
  # available" (Tasks 6 and 7). It is one of `Trash.roots`, and the Trash
  # screen has a Forms tab (Task 4).
  #
  # TEXTS. `submit_label` and `thank_you` are translated with Mobility's
  # jsonb backend, and the fields' labels, help lines and choices are
  # language => text hashes inside `fields`; all of them fall back to the
  # default language and join no translation tracking: no
  # `Translations::Tracker`, no `translation_states` row, nothing in the
  # Translations matrix or AI translation (Global Constraints).
  #
  # KEEPING. A form keeps its submissions only where it says so AND the site
  # has encryption keys (`#keeps?`, owner's ruling 2); `Forms::Save` refuses
  # keeping without them, and a site that loses its keys afterwards keeps
  # nothing more.
  class Form < ApplicationRecord
    extend Mobility
    include Trashable

    self.table_name = "forms"

    MAX_FIELDS = 30
    MAX_CHOICES = 50
    NAME_MAX = 120
    KEEP_DAYS = 1..3650

    translates :submit_label, :thank_you

    # In their order; the rows go with the form (the foreign key cascades).
    has_many :destinations, -> { order(:position, :id) }, class_name: "Forms::Destination", inverse_of: :form
    # A visitor's sends, with their deliveries; they go with the form too
    # (`Trash::Purge`), and otherwise only through `Forms::DeleteSubmissions`.
    has_many :submissions, class_name: "Forms::Submission", inverse_of: :form

    # A backstop for a write that goes around `Forms::Save`, which refuses
    # each of these first with a sentence of its own.
    validates :name, presence: true, length: { maximum: NAME_MAX }
    validates :keep_days, numericality: { only_integer: true, in: KEEP_DAYS }, allow_nil: true

    # The stored list as `Forms::Field` values, in their order. Written whole
    # by `Forms::Save` (`fields=` takes the list of hashes it stores).
    def fields = Array(super).map { |field| Field.from_h(field) }

    # The fields a visitor is shown: those whose type is registered. A field
    # of a type no longer registered (a gem taken out) is dormant: kept in
    # `fields` and carried through every save, but drawn nowhere, by the Form
    # block or the endpoint's own redraw, since drawing one raises in
    # `FieldTypes.fetch`.
    def drawn_fields = fields.select { |field| FieldTypes.find(field.type) }

    # Kept forms with a mail destination: the ones a site without mail set up
    # leaves unable to send (System status's Forms row).
    scope :mailing, -> { kept.where(id: Destination.where(kind: "mail").select(:form_id)) }

    def keeps? = keep_submissions && Encryption.available?

    # Days a submission is kept: the form's own, else the site's default
    # (`site_settings.form_keep_days`, read at every run of the clean-up, so
    # changing it changes those forms' submissions too), or nil when the
    # form keeps nothing.
    def effective_keep_days
      return nil unless keeps?

      keep_days || Current.site.form_keep_days
    end

    # The language's text, else the default language's, else nil (blank:
    # the public key fills in, `public.forms.*`).
    def submit_label_in(locale) = Field.text_in(read_attribute(:submit_label), locale)

    def thank_you_in(locale) = Field.text_in(read_attribute(:thank_you), locale)
  end
end
