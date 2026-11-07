require "test_helper"

# The cookie's reading (`TreeOpenSet`): which branches are drawn open, by the
# one rule both trees and `tree/open_set.js` follow, and what of a cookie is
# kept.
class TreeOpenSetTest < ActiveSupport::TestCase
  test "an opened id opens a branch the default folds, and a folded one folds the root" do
    set = TreeOpenSet.parse("12.-1", readable_ids: [ 1, 12, 40 ])

    assert set.open?(12, root: false, on_path: false), "an opened id is open"
    assert_not set.open?(40, root: false, on_path: false), "a branch below the root is folded by default"
    assert_not set.open?(1, root: true, on_path: false), "a folded entry folds the root"
    assert TreeOpenSet::EMPTY.open?(1, root: true, on_path: false), "the root is open by default"
  end

  test "the path to the selected page is open whatever the folds say" do
    set = TreeOpenSet.parse("-7.-1", readable_ids: [ 1, 7 ])

    assert set.open?(7, root: false, on_path: true)
    assert set.open?(1, root: true, on_path: true)
    assert TreeOpenSet::EMPTY.open?(9, root: false, on_path: true), "a path ancestor is open with no cookie at all"
  end

  test "junk, an id the viewer does not read, a value over 4KB and entries past the limit set nothing" do
    readable = (1..400).to_a + [ 12 ]

    assert_equal "", TreeOpenSet.parse("abc.12x.-", readable_ids: readable).to_s
    assert_equal "", TreeOpenSet.parse("999999", readable_ids: readable).to_s
    assert_not TreeOpenSet.parse("999999", readable_ids: readable).open?(999_999, root: false, on_path: false)
    assert_equal "", TreeOpenSet.parse("1." * 3000, readable_ids: readable).to_s
    assert_equal "", TreeOpenSet.parse(nil, readable_ids: readable).to_s
    assert_equal "", TreeOpenSet.parse("0.-0.01", readable_ids: [ 0, 1 ]).to_s, "an id is a positive number written plainly"

    many = (1..TreeOpenSet::LIMIT + 5).map(&:to_s).join(".")
    kept = TreeOpenSet.parse(many, readable_ids: readable)
    assert kept.open?(TreeOpenSet::LIMIT, root: false, on_path: false)
    assert_not kept.open?(TreeOpenSet::LIMIT + 1, root: false, on_path: false), "an entry past the limit set something"
  end

  test "to_s gives back only what it kept, in its order" do
    set = TreeOpenSet.parse("40.junk.-7.999.12.40.-12", readable_ids: [ 7, 12, 40 ])

    assert_equal "40.-7.12", set.to_s, "junk, an unreadable id and a repeated id are dropped, the first word on an id kept"
  end
end
