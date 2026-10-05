require "test_helper"

# `Page.trash_roots` / `Page.trash_branch_members`: the two halves of a
# trashed branch, as `Trash.roots`, the Trash screen and "Empty trash…" read
# them.
class Page::TrashScopesTest < ActiveSupport::TestCase
  setup do
    Current.actor = users(:one)
    @root = create_page(title: "Branch")
    @member = create_page(title: "Member", parent: @root)
    @deep = create_page(title: "Deep", parent: @member)
    @kept = create_page(title: "Kept")
  end

  def trash(page) = Trash::Move.call(page).tap { |result| assert result.ok?, result.errors.to_sentence }

  test "a trashed branch is one root and its members" do
    trash(@root)

    assert_equal [ @root ], Page.trash_roots.to_a
    assert_equal [ @member, @deep ].sort_by(&:id), Page.trash_branch_members.order(:id).to_a
  end

  test "a page that was never trashed has no trash_root_id and is in neither" do
    assert_nil @kept.trash_root_id
    assert_empty Page.trash_roots
    assert_empty Page.trash_branch_members
  end

  test "a descendant trashed on its own is a root of its own, not a member" do
    trash(@deep)
    trash(@root)

    assert_equal [ @root, @deep ].sort_by(&:id), Page.trash_roots.order(:id).to_a
    assert_equal [ @member ], Page.trash_branch_members.to_a
    assert_equal [ @member ], Page.where(trash_root_id: [ @root.id, @deep.id ]).trash_branch_members.to_a
  end

  test "a trashed page whose root was deleted around it (NULL trash_root_id) is neither" do
    trash(@root)
    @member.update_columns(trash_root_id: nil)

    assert @member.reload.trashed?
    assert_not_includes Page.trashed.trash_roots, @member
    assert_equal [ @deep ], Page.trashed.trash_branch_members.to_a
  end

  test "neither scope looks at trashed_at: the caller narrows" do
    trash(@root)

    assert_equal [ @root ], Page.trashed.trash_roots.to_a
    assert_empty Page.kept.trash_roots
    assert_empty Page.kept.trash_branch_members
  end
end
