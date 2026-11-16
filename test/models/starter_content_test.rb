require "test_helper"

class StarterContentTest < ActiveSupport::TestCase
  test "added? is false before starter content exists" do
    assert_not StarterContent.added?(locale: "en")
  end

  test "added? is true once the sections exist, in whichever locale they were written" do
    StarterContents::Add.call(locale: "de")

    assert StarterContent.added?(locale: "en")
  end

  # Starter sections and sample posts in the trash don't count as "already
  # there": the offer comes back.
  test "trashing the starter sections brings the offer back" do
    StarterContents::Add.call(locale: "en")
    home = Page.find_by(parent_id: nil)
    Current.set(actor: users(:one)) do
      home.children.each { |page| assert Trash::Move.call(page).ok? }
      Post.find_each { |post| assert Trash::Move.call(post).ok? }
    end

    assert_not StarterContent.added?(locale: "en")
  end

  test "the starter sections are the switched-on types'" do
    switch_on_content_types("blog")

    assert_equal [ "Blog" ], StarterContent.sections.map { |section| section[:section][:title] }
  end

  test "sections are the registered content types' own starter declarations, tagged with the type" do
    assert_equal %w[blog resume_entry now_update].sort, StarterContent.sections.map { |section| section[:content_type] }.sort
  end

  test "the starter post is the type's sample" do
    StarterContents::Add.call(locale: "en")

    ContentTypes.all.each do |type|
      post = Post.find_by!(content_type: type.name)
      assert_equal type.sample.title, post.title
      assert_equal type.sample.excerpt.to_s, post.excerpt.to_s
      given = type.sample.fields.stringify_keys.reject { |_name, value| value.blank? }
      assert_equal given, post.metadata.slice(*given.keys)
    end
  end
end
