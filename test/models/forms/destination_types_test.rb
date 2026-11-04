require "test_helper"

# Where a form's submissions go (forms plan, Task 2): a registry of
# destination types, mail built in, a gem's added through
# `ContentSpiel::Plugins.form_destinations`. A destination's secrets are
# sealed one by one and never shown again, as the mail login is.
class Forms::DestinationTypesTest < ActiveSupport::TestCase
  # A deliverer a test registers: the contract is `deliver(delivery, final_attempt:)`.
  module Deliverer
    def self.deliver(_delivery, final_attempt:) = nil
  end

  teardown { Rails.application.reloader.prepare! }

  def mail(recipients) = Forms::Destination.new(form: forms(:contact), kind: "mail", position: 0, settings: { "recipients" => recipients })

  def register_crm
    Forms::DestinationTypes.register("acme/crm", label: "Acme CRM", deliverer: Deliverer) do |d|
      d.field :list, :string, required: true
      d.secret :api_key
    end
  end

  test "mail is built in, with its recipients field" do
    assert_equal %w[mail], Forms::DestinationTypes.names
    mail = Forms::DestinationTypes.fetch("mail")

    assert_kind_of Forms::DestinationType, mail
    assert_equal "Mail", mail.label
    field = mail.fields.sole
    assert_kind_of ContentModel::Definition::Field, field
    assert_equal [ "recipients", :text, true ], [ field.name, field.type, field.required? ]
    assert_empty mail.secrets
    assert_equal Forms::Destinations::Mail, mail.deliverer
    assert_respond_to mail.deliverer, :deliver
    assert_nil Forms::DestinationTypes.find("nope")
    assert_raises(KeyError) { Forms::DestinationTypes.fetch("nope") }
  end

  test "recipients split by lines and commas, refuse a non-address and more than ten" do
    destination = mail("office@example.com, sales@example.com\n\n  help@example.com  \n")
    assert_equal %w[office@example.com sales@example.com help@example.com], destination.recipients
    assert destination.valid?, destination.errors.full_messages.to_sentence

    wrong = mail("office@example.com\nnot an address\nName <x@example.com>")
    assert_not wrong.valid?
    assert_includes wrong.errors[:base], "“not an address” is not one mail address."
    assert_includes wrong.errors[:base], "“Name <x@example.com>” is not one mail address."

    many = mail((1..11).map { |n| "person#{n}@example.com" }.join("\n"))
    assert_not many.valid?
    assert_includes many.errors[:base], "A form mails at most 10 addresses."
    assert mail((1..10).map { |n| "person#{n}@example.com" }.join(",")).valid?

    blank = mail(" \n ")
    assert_not blank.valid?
    assert_includes blank.errors[:base], "Recipients can't be blank."
    assert_empty blank.recipients
  end

  test "a destination of a kind nobody registered is not valid, and has no recipients" do
    destination = Forms::Destination.new(form: forms(:contact), kind: "acme/crm", position: 0, settings: {})
    assert_not destination.valid?
    assert_nil destination.destination_type
    assert_empty destination.recipients
  end

  test "a gem's destination registered through the hook survives a reload" do
    hook = ContentSpiel::Plugins.form_destinations do |destinations|
      destinations.register("acme/crm", label: "Acme CRM", deliverer: Deliverer) do |d|
        d.field :list, :string, required: true
        d.secret :api_key
      end
    end
    Rails.application.reloader.prepare!
    assert_equal %w[mail acme/crm], Forms::DestinationTypes.names
    Rails.application.reloader.prepare!
    crm = Forms::DestinationTypes.fetch("acme/crm")
    assert_equal [ "Acme CRM", %w[list], %w[api_key], Deliverer ], [ crm.label, crm.fields.map(&:name), crm.secrets, crm.deliverer ]
    assert_equal %w[short_text long_text email choice checkbox], Forms::FieldTypes.names, "the field types' registry is not touched"

    ContentSpiel::Plugins.remove(hook)
    Rails.application.reloader.prepare!
    assert_equal %w[mail], Forms::DestinationTypes.names
  ensure
    ContentSpiel::Plugins.remove(hook) if hook
  end

  test "a gem's destination with a bare name is refused, naming the place of the call" do
    line = __LINE__ + 1
    bare = ContentSpiel::Plugins.form_destinations { |destinations| destinations.register("crm", label: "CRM", deliverer: Deliverer) }
    error = assert_raises(ArgumentError) { ContentSpiel::Plugins.register_form_destinations(Forms::DestinationTypes) }
    assert_includes error.message, "owner/name"
    assert_includes error.message, "#{__FILE__}:#{line}"
  ensure
    ContentSpiel::Plugins.remove(bare) if bare
  end

  test "a registration is refused when it is malformed" do
    assert_raises(ArgumentError) { Forms::DestinationTypes.register("mail", label: "Mail again", deliverer: Deliverer) }
    assert_raises(ArgumentError) { Forms::DestinationTypes.register("acme/crm", label: "", deliverer: Deliverer) }
    assert_raises(ArgumentError) { Forms::DestinationTypes.register("acme/crm", label: "CRM", deliverer: Object.new) }
    assert_raises(ArgumentError) { Forms::DestinationTypes.register("Acme CRM", label: "CRM", deliverer: Deliverer) }
    assert_raises(ArgumentError) { Forms::DestinationTypes.register("acme/crm", label: "CRM", deliverer: Deliverer) { |d| d.field :list, :nope } }
    assert_raises(ArgumentError) { Forms::DestinationTypes.register("acme/crm", label: "CRM", deliverer: Deliverer) { |d| d.field :list, :string, translated: true } }
    assert_raises(ArgumentError) { Forms::DestinationTypes.register("acme/crm", label: "CRM", deliverer: Deliverer) { |d| d.secret "API key" } }
    assert_raises(ArgumentError) do
      Forms::DestinationTypes.register("acme/crm", label: "CRM", deliverer: Deliverer) do |d|
        d.field :api_key, :string
        d.secret :api_key
      end
    end
    assert_nil Forms::DestinationTypes.find("acme/crm"), "a refused registration leaves nothing behind"
  end

  test "a destination's secret is set or not without being decrypted" do
    register_crm
    destination = Forms::Destination.create!(form: forms(:newsletter), kind: "acme/crm", position: 0, settings: { "list" => "subscribers" })
    assert_not destination.secret_set?(:api_key)

    destination.write_secrets!("api_key" => "s3cret-value")
    assert destination.secret_set?("api_key")
    assert_not destination.secret_set?("other")
    assert_not_includes destination.read_attribute_before_type_cast(:secrets).to_s, "s3cret-value", "the value is sealed"

    destination.reload
    without_encryption_keys do
      assert destination.secret_set?(:api_key), "presence is read off the stored ciphertext, with no key to decrypt it"
    end
    assert_equal "s3cret-value", destination.secret(:api_key)
    assert_not_nil destination.secrets_saved_at
  end
end
