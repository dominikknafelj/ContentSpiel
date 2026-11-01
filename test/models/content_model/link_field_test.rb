require "test_helper"

# The `:link` field type: an address a visitor follows from a page, so what
# a browser could read as another host (or as script) is refused. `:url`
# keeps its own, wider rule.
class ContentModel::LinkFieldTest < ActiveSupport::TestCase
  setup do
    @definition = ContentModel::BlockTypeDefinition.new("sample").tap do |t|
      t.field :target, :link
      t.field :plain, :url
    end
  end

  def fields(values) = ContentModel::FieldSet.for(@definition).new({}).assign(values)

  test "a link takes http, https and mailto addresses and a site-relative one" do
    [ "https://example.com/a", "HTTP://EXAMPLE.COM", "mailto:a@b.example", "/about", "/about?x=1#y", "/" ].each do |value|
      assert fields("target" => value).valid?, "#{value.inspect} is a link"
    end
  end

  test "a link refuses another host by //, javascript:, data:, a bare word and a relative path" do
    [ "//host", "javascript:alert(1)", "data:text/html,x", "about", "about/us", "JaVaScRiPt:alert(1)", "ftp://host/x", "https:", "#top" ].each do |value|
      set = fields("target" => value)

      assert_not set.valid?, "#{value.inspect} is no link"
      assert_includes set.errors.details[:target].map { |detail| detail[:error] }, :invalid
    end
  end

  test "a link that a browser would send to another host is refused: a backslash, white space and control characters, wherever they stand" do
    [ "/\\evil.example", "\\\\evil", "/ /evil", "/a\tb", "/a\nb", "/\t/evil", "/\n/evil", "/\r/evil", "/\u0000/evil", "/\u007F/evil",
      "https://a b.example", "https://a\\b.example", "/a b", "/ /evil", " /about", "javascript\t:alert(1)", "java\nscript:alert(1)" ].each do |value|
      assert_not link?(value), "#{value.inspect} is no link"
    end
  end

  test "link? is the one rule, and the field validates by it" do
    assert ContentModel::FieldTypes.link?("/about")
    assert_not ContentModel::FieldTypes.link?("//evil")
    assert_not ContentModel::FieldTypes.link?(nil)
    assert_not ContentModel::FieldTypes.link?(42)
    assert_not ContentModel::FieldTypes.link?("")
  end

  test "a link is cast stripped and blank is nothing, and :url is unchanged" do
    assert_equal "/a", fields("target" => "  /a  ").target
    assert_nil fields("target" => "   ").target
    assert fields("target" => "").valid?
    assert fields("plain" => "https://example.com").valid?
    assert_not fields("plain" => "/about").valid?
  end

  test "a link field can't be translated" do
    error = assert_raises(ArgumentError) { ContentModel::Definition.new("x").field(:a, :link, translated: true) }
    assert_equal "link fields can't be translated (the address is the same in every language)", error.message
  end

  private

  def link?(value) = ContentModel::FieldTypes.link?(value)
end
