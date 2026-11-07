require "test_helper"

class Admin::ShellHelperTest < ActionView::TestCase
  include Admin::ShellHelper

  test "the column holds the Pages tree unless the screen names its subject" do
    assert_equal "pages", admin_tree_subject

    content_for :tree_label, "mind_graph"
    assert_equal "mind_graph", admin_tree_subject
    assert_instance_of String, admin_tree_subject
  end

  test "a subject that is not one raises" do
    content_for :tree_label, "posts"
    assert_raises(KeyError) { admin_tree_subject }
  end

  test "the mind graph's list fills the column, and the Pages tree does not" do
    assert Admin::Shell::TreeSubjects.fill?("mind_graph")
    assert_not Admin::Shell::TreeSubjects.fill?("pages")
    assert_equal "components.shell.tree_subject.mind_graph.hide", Admin::Shell::TreeSubjects.key("mind_graph", :hide)
    assert_raises(KeyError) { Admin::Shell::TreeSubjects.key("pages", :title) }
  end

  test "every subject has every word" do
    Admin::Shell::TreeSubjects::ALL.each_key do |subject|
      Admin::Shell::TreeSubjects::WORDS.each do |word|
        assert I18n.exists?("admin.#{Admin::Shell::TreeSubjects.key(subject, word)}", :en), "#{subject} has no #{word}"
      end
    end
  end
end
