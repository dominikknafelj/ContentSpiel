require "test_helper"

class ContentModel::FieldSetTest < ActiveSupport::TestCase
  setup do
    @definition = ContentModel::ContentTypeDefinition.new("event").tap do |t|
      t.field :venue, :string, required: true
      t.field :seats, :integer, min: 1
      t.field :starts_on, :date
      t.field :website, :url
      t.field :kind, :select, options: { "talk" => "Talk", "workshop" => "Workshop" }
      t.field :listed, :boolean, default: true
      t.field :headline, :string, translated: true
    end
    FieldGroups.register("test/speaker") { |c| c.field :name, :string, required: true; c.field :url, :url }
    @with_groups = ContentModel::ContentTypeDefinition.new("conference").tap do |t|
      t.field :speakers, :groups, of: "test/speaker"
      t.field :lead, :group, of: "test/speaker", translated: true
    end
  end

  teardown { FieldGroups.reset! ; Rails.application.reloader.prepare! }

  test "casts, defaults and validates scalar fields" do
    fields = ContentModel::FieldSet.for(@definition).new({ "venue" => "Hall", "seats" => "12", "starts_on" => "2026-10-01", "kind" => "talk" })
    assert fields.valid?, fields.errors.full_messages.to_sentence
    assert_equal 12, fields.seats
    assert_equal Date.new(2026, 10, 1), fields.starts_on
    assert_equal true, fields.listed
  end

  test "blank strings cast to nil for every scalar type" do
    fields = ContentModel::FieldSet.for(@definition).new({ "venue" => "Hall", "seats" => "", "starts_on" => "", "website" => "", "kind" => "" })
    assert_nil fields.seats
    assert_nil fields.starts_on
    assert_nil fields.website
    assert_nil fields.kind
    assert fields.valid?
    assert_equal({ "venue" => "Hall", "listed" => true }, fields.untranslated_hash)
  end

  test "required, min, select, date and url errors are keyed by field" do
    fields = ContentModel::FieldSet.for(@definition).new({ "seats" => "0", "starts_on" => "not a date", "website" => "javascript:alert(1)", "kind" => "party" })
    assert_not fields.valid?
    %w[venue seats starts_on website kind].each { |key| assert fields.errors[key].any?, "expected an error on #{key}" }
  end

  test "translated field reads fall back publicly and stay literal otherwise" do
    site_settings(:default).update!(default_locale: "de")
    translations = { "de" => { "headline" => "Hallo" } }
    literal = ContentModel::FieldSet.for(@definition).new({ "venue" => "Hall" }, translations, locale: "en")
    public_read = ContentModel::FieldSet.for(@definition).new({ "venue" => "Hall" }, translations, locale: "en", fallback: true)
    assert_nil literal.headline
    assert_equal "Hallo", public_read.headline
  end

  test "groups: nested validation with path keys and whole-group translation" do
    fields = ContentModel::FieldSet.for(@with_groups).new(
      { "speakers" => [ { "name" => "Ada" }, { "name" => "" } ] },
      { "en" => { "lead" => { "name" => "Grace" } } }, locale: "en")
    assert_not fields.valid?
    assert fields.errors["speakers.1.name"].any?
    assert_equal "Ada", fields.group(:speakers).first.name
    assert_equal "Grace", fields.group(:lead).name
    assert_equal({ "lead" => { "name" => "Grace" } }, fields.translated_hash)
  end

  test "assign writes translated keys for the instance locale only" do
    fields = ContentModel::FieldSet.for(@definition).new({}, {}, locale: "de")
    fields.assign("venue" => "Saal", "headline" => "Hallo")
    assert_equal({ "venue" => "Saal" }, fields.untranslated_hash.slice("venue"))
    assert_equal({ "headline" => "Hallo" }, fields.translated_hash)
  end

  # `group`/`groups` values arrive as jsonb read straight back from the
  # database (or, for `groups`, from an admin form's `has_many`-shaped
  # params -- an Array of Hashes only when nothing's gone wrong). A stray
  # non-Hash value -- a hand-edited row, a plugin's own bug -- must come back
  # as an ordinary validation error, the same as any other bad input, not as
  # a `NoMethodError` from `Hash`-only jsonb code assuming its shape.
  test "a non-hash group value is an :invalid error, not a crash" do
    fields = ContentModel::FieldSet.for(@with_groups).new({}, { "en" => { "lead" => "not a hash" } }, locale: "en")
    assert_nothing_raised { fields.valid? }
    assert_not fields.valid?
    assert fields.errors["lead"].any?
    assert_nothing_raised { fields.group(:lead) }
    assert_nil fields.group(:lead)
  end

  test "a non-array groups value is an :invalid error, not a crash" do
    fields = ContentModel::FieldSet.for(@with_groups).new({ "speakers" => "not an array" })
    assert_nothing_raised { fields.valid? }
    assert_not fields.valid?
    assert fields.errors["speakers"].any?
    assert_nothing_raised { fields.group(:speakers) }
  end

  test "a groups list with a non-hash item is an :invalid error, not a crash" do
    fields = ContentModel::FieldSet.for(@with_groups).new({ "speakers" => [ { "name" => "Ada" }, "not a hash" ] })
    assert_nothing_raised { fields.valid? }
    assert_not fields.valid?
    assert fields.errors["speakers"].any?
    assert_nothing_raised { fields.group(:speakers) }
  end

  test "group fields can't declare a default" do
    assert_raises(ArgumentError) do
      ContentModel::ContentTypeDefinition.new("thing").tap { |t| t.field :speakers, :groups, of: "test/speaker", default: [] }
    end
  end
end
