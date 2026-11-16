require "test_helper"

class Media::PlaceTest < ActiveSupport::TestCase
  setup do
    @folder = Media::Folder.create!(name: "Client A")
    @tree = Media::FolderTree.load
  end

  test "absent and all are All media, none is Not in a folder, an id of the tree is that folder, anything else is nil" do
    [ nil, "", "all" ].each { |raw| assert_equal Media::Place::ALL, Media::Place.parse(raw, tree: @tree), raw.inspect }
    assert_equal Media::Place::NONE, Media::Place.parse("none", tree: @tree)

    place = Media::Place.parse(@folder.id.to_s, tree: @tree)
    assert_equal @folder.id, place.folder
    assert_equal @folder.id.to_s, place.to_param

    [ [ @folder.id.to_s ], "#{@folder.id}x", (@folder.id + 1).to_s, "-1", "0", "99999999999999999999", "None", { "a" => "1" } ].each do |raw|
      assert_nil Media::Place.parse(raw, tree: @tree), raw.inspect
    end
  end

  test "to_param and the two predicates" do
    assert_equal "all", Media::Place::ALL.to_param
    assert_equal "none", Media::Place::NONE.to_param
    assert Media::Place::ALL.all?
    assert Media::Place::NONE.none?
    assert_not Media::Place::NONE.all?
  end

  test "narrow keeps All media whole, takes the images outside any folder, or a folder's own" do
    inside = create_media_asset.tap { |asset| asset.update_columns(folder_id: @folder.id) } # version: none (a test's own rows)
    outside = create_media_asset

    assert_equal [ inside, outside ].map(&:id).sort, Media::Place::ALL.narrow(Media::Asset).ids.sort
    assert_equal [ outside.id ], Media::Place::NONE.narrow(Media::Asset).ids
    assert_equal [ inside.id ], Media::Place.parse(@folder.id.to_s, tree: @tree).narrow(Media::Asset).ids
  end
end
