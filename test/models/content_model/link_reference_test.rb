require "test_helper"

# The second thing a `:link` field holds beside an address (#145): a reference
# to one page or post, `cs:page/12`, the spelling rich text's Markdown already
# gives an `internalLink`. `link?` does not change: it is what a browser may
# follow, and a reference is not that.
class ContentModel::LinkReferenceTest < ActiveSupport::TestCase
  Types = ContentModel::FieldTypes

  setup do
    @definition = ContentModel::BlockTypeDefinition.new("sample").tap { |t| t.field :target, :link }
    @page = create_page(title: "Target")
  end

  def fields(values, stored = {}) = ContentModel::FieldSet.for(@definition).new({}, stored: stored).assign(values)

  test "a well formed reference parses to its type and id, and is no address a browser may follow" do
    reference = ContentModel::LinkReference.parse("cs:page/12")
    assert_equal [ "page", 12 ], [ reference.type, reference.id ]
    assert_equal "post", ContentModel::LinkReference.parse("cs:post/7").type
    assert_not Types.link?("cs:page/12")
    assert Types.link_value?("cs:page/12")
    assert Types.link_value?("/about")
    assert_not Types.link_value?("about")
  end

  test "anything else is no reference, whatever the value, and never raises" do
    [ nil, 12, [], {}, "", "cs:", "cs:page", "cs:page/", "cs:page/abc", "cs:page/0", "cs:page/012", "cs:page/-1", "cs:page/1.5", "cs:page/1/2",
      "cs:page/1 ", " cs:page/1", "cs:page/1\n", "\ncs:page/1", "CS:page/1", "cs:PAGE/1", "cs:user/1", "cs:media/1", "cs://page/1", "cs:page/1?x", "cs:page/1#x",
      "cs:page/#{"1" * 19}", "cs:page/١", "cs:page/1\xFF", "cs:page/1\xFF".b, "cs:page/1".b, "/about", "#team" ].each do |value|
      assert_nil ContentModel::LinkReference.parse(value), "#{value.inspect} is no reference"
    end
  end

  test "a malformed reference is refused with the field's own error" do
    [ "cs:page/abc", "cs:widget/1", "cs:page/0", "cs:page/1/2", "CS:page/1" ].each do |value|
      set = fields("target" => value)
      assert_not set.valid?, "#{value.inspect} is refused"
      assert_includes set.errors.details[:target].map { |detail| detail[:error] }, :invalid
    end
  end

  test "a well formed reference is taken with its outer white space off, whatever it names and whoever asks" do
    set = fields("target" => " cs:page/#{@page.id} ")
    assert set.valid?
    assert_equal "cs:page/#{@page.id}", set.untranslated_hash["target"]

    assert fields("target" => "cs:page/999999").valid?, "a target that is gone stays stored and draws nothing"
    as(users(:editor_branch)) { assert fields("target" => "cs:page/#{@page.id}").valid? }
  end
end
