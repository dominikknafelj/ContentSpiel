require "test_helper"

# A form's one write (forms plan, Task 2): its name, fields, keeping and
# destinations saved whole by an explicit Save, authorized as `forms.manage`,
# audited, and moving the public content version (a form has no published
# copy: every write that changes what a placed form draws moves it).
class Forms::SaveTest < ActiveSupport::TestCase
  setup { Current.actor = users(:one) }

  # A destination type with a secret, for the secret cases.
  module Deliverer
    def self.deliver(_delivery, final_attempt:) = nil
  end

  def register_crm
    Forms::DestinationTypes.register("acme/crm", label: "Acme CRM", deliverer: Deliverer) do |d|
      d.field :list, :string, required: true
      d.secret :api_key
    end
  end

  def sentence(key, **values) = Forms::Save.sentence(key, **values)

  def field(label, type: "short_text", key: nil, required: false, **settings)
    { key: key, type: type, required: required, label: { "en" => label }, help: {}, settings: settings }
  end

  def mail_to(recipients = "office@example.com") = { kind: "mail", settings: { recipients: recipients }, secrets: {} }

  def save(form = Forms::Form.new, attributes: { name: "Enquiry" }, fields: [ field("Your name") ], destinations: [ mail_to ])
    Forms::Save.call(form, attributes: attributes, fields: fields, destinations: destinations)
  end

  def assert_refused(expected, form: Forms::Form.new, **call)
    counts = [ Forms::Form.count, Forms::Destination.count, Audit::Event.count ]
    stored = Forms::Form.order(:id).map(&:attributes)
    result = save(form, **call)

    assert_not result.ok?, "expected the refusal #{expected.inspect}"
    assert_includes result.errors, expected
    assert_equal counts, [ Forms::Form.count, Forms::Destination.count, Audit::Event.count ], "nothing is written"
    assert_equal stored, Forms::Form.order(:id).map(&:attributes)
    result
  end

  test "a new form with two fields and a mail saves, keys are made for new fields and kept for existing ones" do
    result = save(fields: [ field("Your name", required: true), field("Email address", type: "email", key: "f_madeup01") ])

    assert result.ok?, result.errors.to_sentence
    form = result.record.reload
    assert_equal "Enquiry", form.name
    assert_equal %w[short_text email], form.fields.map(&:type)
    assert(form.fields.all? { |stored| stored.key.match?(Forms::Field::KEY_FORMAT) })
    assert_not_equal "f_madeup01", form.fields.second.key, "a key the form does not have is not taken"
    assert_equal [ true, false ], form.fields.map(&:required)
    assert_equal [ [ "mail", { "recipients" => "office@example.com" } ] ], form.destinations.map { |d| [ d.kind, d.settings ] }

    event = Audit::Event.find_by!(action: "form.created", subject: form)
    assert_equal "Enquiry", event.subject_label

    kept_key = form.fields.first.key
    again = save(form, attributes: { name: "Enquiry" }, fields: [ field("Your name", key: kept_key), field("Phone", key: "") ])
    assert again.ok?, again.errors.to_sentence
    assert_equal kept_key, form.reload.fields.first.key
    assert_match Forms::Field::KEY_FORMAT, form.fields.second.key
  end

  test "reordering and relabelling keep every field's key, and a choice's key" do
    form = forms(:newsletter)
    mail, topic, consent = form.fields
    reordered = [
      field("I agree", type: "checkbox", key: consent.key, required: true),
      { key: topic.key, type: "choice", required: false, label: { "en" => "Subject" }, help: {},
        settings: { display: "dropdown", choices: [ { key: "c_offr0001", label: { "en" => "Special offers" } }, { key: "", label: { "en" => "Events" } } ] } },
      field("Your email", type: "email", key: mail.key, required: true)
    ]

    result = save(form, attributes: { name: "Newsletter", keep_submissions: true }, fields: reordered, destinations: [])
    assert result.ok?, result.errors.to_sentence

    saved = form.reload.fields
    assert_equal [ consent.key, topic.key, mail.key ], saved.map(&:key)
    assert_equal [ "I agree", "Subject", "Your email" ], saved.map { |stored| stored.label_in("en") }
    assert_equal "c_offr0001", saved.second.choices.first.key
    assert_match Forms::Choice::KEY_FORMAT, saved.second.choices.second.key
    assert_equal "dropdown", saved.second.settings["display"]
    assert_equal "form.updated", Audit::Event.where(subject: form).order(:id).last.action
  end

  test "a blank name is refused" do
    assert_refused sentence(:name_blank), attributes: { name: "  " }
  end

  test "a name over the limit is refused" do
    assert_refused sentence(:name_too_long, count: Forms::Form::NAME_MAX), attributes: { name: "x" * (Forms::Form::NAME_MAX + 1) }
  end

  test "more than 30 fields are refused" do
    assert_refused sentence(:too_many_fields, count: 30), fields: (1..31).map { |n| field("Field #{n}") }
  end

  test "a field without a label in the default language is refused" do
    with_locales(%w[en de], default: "en") do
      unlabelled = { key: nil, type: "short_text", required: false, label: { "de" => "Name" }, help: {}, settings: {} }
      assert_refused sentence(:label_missing, position: 2, language: "English"), fields: [ field("First"), unlabelled ]
    end
  end

  test "a choice field with no choices, or more than 50, is refused" do
    none = field("Topic", type: "choice", choices: [])
    assert_refused sentence(:choices_missing, field: "Topic"), fields: [ none ]

    many = field("Topic", type: "choice", choices: (1..51).map { |n| { key: "", label: { "en" => "Choice #{n}" } } })
    assert_refused sentence(:too_many_choices, field: "Topic", count: 50), fields: [ many ]
  end

  test "a choice without a label in the default language is refused" do
    unlabelled = field("Topic", type: "choice", choices: [ { key: "", label: { "en" => "One" } }, { key: "", label: {} } ])
    assert_refused sentence(:choice_label_missing, field: "Topic", language: "English"), fields: [ unlabelled ]
  end

  test "an unknown field type or destination is refused" do
    assert_refused sentence(:unknown_field_type, type: "acme/rating"), fields: [ field("Stars", type: "acme/rating") ]
    assert_refused sentence(:unknown_destination, kind: "acme/crm"), destinations: [ { kind: "acme/crm", settings: {}, secrets: {} } ]
  end

  test "a destination whose settings are wrong is refused with the type's sentence" do
    assert_refused "“nobody” is not one mail address.", destinations: [ mail_to("nobody") ]
  end

  test "a form that neither keeps nor has a destination is refused" do
    result = assert_refused sentence(:nowhere), attributes: { name: "Enquiry", keep_submissions: false }, destinations: []
    assert_equal "A form needs somewhere to send its submissions: keep them, or add a mail.", result.errors.sole
  end

  test "keep on without encryption keys is refused with the sentence" do
    with_singleton_override(Forms::Encryption, :available?, -> { false }) do
      result = assert_refused sentence(:no_encryption_keys), attributes: { name: "Enquiry", keep_submissions: true }
      assert_equal "This site has no encryption keys, so submissions can't be kept. See Hosting: encryption keys.", result.errors.sole
    end
    with_singleton_override(Forms::Encryption, :available?, -> { false }) do
      assert save(attributes: { name: "Enquiry", keep_submissions: false }).ok?, "a form that only mails saves without keys"
    end
  end

  test "keep_days outside 1 to 3650 is refused, and blank follows the site" do
    [ 0, 3651, -5, "soon" ].each do |days|
      assert_refused sentence(:keep_days, min: 1, max: 3650), attributes: { name: "Enquiry", keep_submissions: true, keep_days: days }
    end

    result = save(attributes: { name: "Enquiry", keep_submissions: true, keep_days: "" })
    assert result.ok?, result.errors.to_sentence
    assert_nil result.record.reload.keep_days
    assert save(result.record, attributes: { name: "Enquiry", keep_submissions: true, keep_days: "3650" }).ok?
    assert_equal 3650, result.record.reload.keep_days
  end

  test "a trashed form is not saved" do
    form = forms(:contact)
    form.update_columns(trashed_at: Time.current)
    assert_refused sentence(:trashed), form: form, attributes: { name: "Contact" }
  end

  test "the submit label and thank-you are saved per language, a blank language dropped" do
    with_locales(%w[en de], default: "en") do
      result = save(attributes: { name: "Enquiry", submit_label: { "en" => "Send", "de" => "Senden" }, thank_you: { "en" => "Thanks.", "de" => " " } })
      assert result.ok?, result.errors.to_sentence

      form = result.record.reload
      assert_equal [ "Senden", "Send" ], [ form.submit_label_in("de"), form.submit_label_in("en") ]
      assert_equal "Thanks.", form.thank_you_in("de"), "the blank German falls back"
      assert_equal({ "en" => "Thanks." }, form.read_attribute(:thank_you))
    end
  end

  test "a text under a code that is no language this CMS serves is refused" do
    assert_refused sentence(:unknown_languages, codes: "xx"), attributes: { name: "Enquiry", submit_label: { "xx" => "Envoyer" } }
  end

  # Fix round 1: a language turned off keeps its texts for the day it is
  # turned on again, as `Locales::Disable` keeps content's; a save in between
  # must neither be refused nor lose them.
  test "a form's texts in a language that was turned off survive a save and are back when it is turned on" do
    with_locales(%w[en de], default: "en") do
      topic = { key: nil, type: "choice", required: false, label: { "en" => "Topic", "de" => "Thema" }, help: { "de" => "Bitte wählen" },
        settings: { choices: [ { key: nil, label: { "en" => "News", "de" => "Neues" } } ] } }
      result = save(attributes: { name: "Enquiry", submit_label: { "en" => "Send", "de" => "Senden" } }, fields: [ topic ])
      assert result.ok?, result.errors.to_sentence
    end
    form = result_form = Forms::Form.order(:id).last
    stored = form.fields.sole

    assert Locales::Disable.call("de").ok?
    # What the screen sends with German off: the English texts alone, and a
    # German text it no longer shows, which is dropped rather than refused.
    edited = { key: stored.key, type: "choice", required: true, label: { "en" => "Subject", "de" => "Betreff" }, help: {},
      settings: { choices: [ { key: stored.choices.sole.key, label: { "en" => "Updates" } } ] } }
    again = save(form.reload, attributes: { name: "Enquiry", submit_label: { "en" => "Send it", "de" => "Los" } }, fields: [ edited ])
    assert again.ok?, again.errors.to_sentence

    assert Locales::Enable.call("de").ok?
    result_form.reload
    field = result_form.fields.sole
    assert_equal [ "Subject", "Thema" ], [ field.label_in("en"), field.label_in("de") ], "the German label is the stored one, not the dropped one"
    assert_equal "Bitte wählen", field.help_in("de")
    assert_equal [ "Updates", "Neues" ], [ field.choices.sole.label_in("en"), field.choices.sole.label_in("de") ]
    assert_equal [ "Send it", "Senden" ], [ result_form.submit_label_in("en"), result_form.submit_label_in("de") ]
  end

  # Fix round 1: a destination is matched by its id alone, so a stored
  # secret stays with its own row.
  test "removing the first of two destinations of one kind leaves the second its own secret" do
    register_crm
    first = { kind: "acme/crm", settings: { list: "first" }, secrets: { api_key: "first-secret" } }
    second = { kind: "acme/crm", settings: { list: "second" }, secrets: { api_key: "second-secret" } }
    result = save(destinations: [ first, second ])
    assert result.ok?, result.errors.to_sentence
    form = result.record
    kept = form.destinations.find_by!(position: 1)

    again = save(form.reload, attributes: { name: "Enquiry" }, destinations: [ second.merge(id: kept.id, secrets: { api_key: "" }) ])
    assert again.ok?, again.errors.to_sentence
    remaining = form.reload.destinations.sole
    assert_equal [ kept.id, "second", "second-secret" ], [ remaining.id, remaining.settings["list"], remaining.secret(:api_key) ]

    without_id = save(form.reload, attributes: { name: "Enquiry" }, destinations: [ second.merge(secrets: { api_key: "" }) ])
    assert without_id.ok?, without_id.errors.to_sentence
    fresh = form.reload.destinations.sole
    assert_not_equal kept.id, fresh.id, "a destination given without an id is a new row"
    assert_not fresh.secret_set?(:api_key), "and holds no other row's secret"
  ensure
    Rails.application.reloader.prepare!
  end

  test "a blank secret keeps the stored one, and the audit snapshot holds no secret" do
    register_crm
    crm = { kind: "acme/crm", settings: { list: "subscribers" }, secrets: { api_key: "s3cret-value" } }
    result = save(destinations: [ crm ])
    assert result.ok?, result.errors.to_sentence
    destination = result.record.destinations.sole
    assert_equal "s3cret-value", destination.secret(:api_key)
    first_saved_at = destination.secrets_saved_at
    assert_equal({ "Destination 1 credentials" => [ "not set", "set" ] }, Audit::Event.find_by!(action: "form.created", subject: result.record).field_changes.slice("Destination 1 credentials"))
    crm = crm.merge(id: destination.id)

    updated_at = result.record.reload.updated_at
    version = PublicSite::Version.current
    travel 1.minute do
      again = save(result.record, attributes: { name: "Enquiry" }, fields: result.record.fields.map(&:to_h), destinations: [ crm.merge(secrets: { api_key: "" }) ])
      assert again.ok?, again.errors.to_sentence
    end
    destination = result.record.reload.destinations.sole
    assert_equal "s3cret-value", destination.secret(:api_key), "a blank secret keeps the stored one"
    assert_equal first_saved_at, destination.secrets_saved_at
    assert_equal updated_at, result.record.updated_at, "a blank secret is no change: nothing is touched"
    assert_equal version, PublicSite::Version.current

    travel 2.minutes do
      save(result.record, attributes: { name: "Enquiry" }, fields: result.record.fields.map(&:to_h), destinations: [ crm.merge(secrets: { api_key: "n3w-value" }) ])
    end
    assert_equal "n3w-value", result.record.reload.destinations.sole.secret(:api_key)
    assert_operator result.record.updated_at, :>, updated_at, "a secret written moves the builder's stale base"
    assert_equal version, PublicSite::Version.current, "and moves no content version: a secret is on no public page"
    assert_equal [ "set", "set" ], Audit::Event.where(subject: result.record).order(:id).last.field_changes["Destination 1 credentials"]

    events = Audit::Event.where(subject: result.record)
    assert_operator events.count, :>=, 2
    events.each do |event|
      text = [ event.snapshot, event.field_changes, event.metadata ].to_json
      assert_not_includes text, "s3cret-value"
      assert_not_includes text, "n3w-value"
    end
    assert_equal [ "api_key" ], events.last.snapshot["destinations"].sole["secrets_set"]
    assert_not events.last.snapshot.key?("secrets")
  ensure
    Rails.application.reloader.prepare!
  end

  test "a secret on a site without encryption keys is refused with its sentence, and nothing is written" do
    register_crm
    crm = { kind: "acme/crm", settings: { list: "subscribers" }, secrets: { api_key: "s3cret-value" } }
    result = without_encryption_keys do
      assert_refused sentence(:no_encryption_keys_for_secret), destinations: [ crm ]
    end
    assert_equal [ sentence(:no_encryption_keys_for_secret) ], result.errors
  ensure
    Rails.application.reloader.prepare!
  end

  test "a refused save leaves the caller's form showing its stored destinations" do
    form = forms(:contact)
    assert_not save(form, attributes: { name: "" }, destinations: [ mail_to("else@example.com") ]).ok?
    assert_equal({ "recipients" => "office@example.com" }, form.destinations.sole.settings)
  end

  test "a save moves the public content version" do
    before = PublicSite::Version.current
    assert save.ok?
    assert_operator PublicSite::Version.current, :>, before
  end

  test "a save that changes nothing records nothing and moves nothing" do
    form = forms(:contact)
    fields = form.fields.map(&:to_h)
    attributes = { name: form.name, keep_submissions: false, submit_label: { "en" => "Send" }, thank_you: { "en" => "Thank you, we'll be in touch." } }
    before = PublicSite::Version.current

    assert_no_difference -> { Audit::Event.count } do
      assert save(form, attributes: attributes, fields: fields, destinations: [ mail_to ]).ok?
    end
    assert_equal before, PublicSite::Version.current
  end

  test "a form's texts make no translation_states row" do
    with_locales(%w[en de], default: "en") do
      assert_no_difference -> { Translations::State.count } do
        assert save(attributes: { name: "Enquiry", submit_label: { "en" => "Send", "de" => "Senden" } }).ok?
      end
    end
    assert_not Translations::State.exists?(record_type: "Forms::Form")
  end

  test "it needs forms.manage, and a refusal writes nothing but the denial" do
    reader = users(:reader)
    Current.actor = reader
    result = save(forms(:contact), attributes: { name: "Renamed" })

    assert_predicate result, :denied?
    assert_equal "Contact", forms(:contact).reload.name
    denial = Audit::Event.order(:id).last
    assert_equal [ "access.denied", "forms.manage" ], [ denial.action, denial.metadata["permission"] ]
  end
  test "a save that changes only the destinations moves the form's updated_at and not the content version" do
    form = forms(:contact)
    before = form.updated_at
    version = PublicSite::Version.current
    travel 1.minute do
      result = save(form, attributes: {}, fields: form.fields.map(&:to_h),
        destinations: [ mail_to("office@example.com").merge(id: form_destinations(:contact_mail).id), mail_to("second@example.com") ])
      assert result.ok?, result.errors.to_sentence
    end
    assert_operator form.reload.updated_at, :>, before, "the builder's stale base moves"
    assert_equal version, PublicSite::Version.current, "a destination is on no public page"
    assert_equal 2, form.destinations.count
  end
end
