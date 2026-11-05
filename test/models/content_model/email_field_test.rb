require "test_helper"

# The `:email` field type: one plain address, the rule
# mail's sender address is held to (`MailSettings.one_address?`), at most 254
# characters (RFC 5321's path limit). `:text` takes `max:` as `:code` does.
class ContentModel::EmailFieldTest < ActiveSupport::TestCase
  setup do
    @definition = ContentModel::BlockTypeDefinition.new("sample").tap do |t|
      t.field :address, :email
      t.field :note, :text, max: 5
    end
  end

  def fields(values) = ContentModel::FieldSet.for(@definition).new({}).assign(values)

  test "an email field takes one plain address and refuses two, a name with spaces and 255 characters" do
    assert fields("address" => " ada@example.com ").valid?
    assert_equal "ada@example.com", fields("address" => " ada@example.com ").address

    [ "ada@example.com, bob@example.com", "Ada Lovelace <ada@example.com>", "ada lovelace@example.com", "no-at-sign", "ada@" ].each do |bad|
      assert_not fields("address" => bad).valid?, "#{bad.inspect} is refused"
    end

    long = "#{"a" * 243}@example.com"
    assert_equal 255, long.length
    over = fields("address" => long)
    assert_not over.valid?
    assert_equal :too_long, over.errors.first.type
    assert fields("address" => "#{"a" * 242}@example.com").valid?, "254 characters are fine"
  end

  test "an email field is never translated" do
    error = assert_raises(ArgumentError) { ContentModel::BlockTypeDefinition.new("x").field(:address, :email, translated: true) }
    assert_includes error.message, "email"
    assert_not ContentModel::FieldTypes.fetch(:email).translatable
    assert_equal :value, ContentModel::FieldTypes.fetch(:email).audit
  end

  test "a text field takes max: as a positive Integer and refuses a longer value in the words of the code field" do
    over = fields("note" => "abcdef")
    assert_not over.valid?
    assert_equal [ "is too long (maximum is 5 characters)" ], over.errors[:note]
    assert_equal :too_long, over.errors.first.type
    assert fields("note" => "abcde").valid?

    [ 0, -1, "5", 2.5 ].each do |bad|
      assert_raises(ArgumentError) { ContentModel::BlockTypeDefinition.new("x").field(:note, :text, max: bad) }
    end
  end
end
