require "test_helper"

class Admin::FieldParamsTest < ActiveSupport::TestCase
  test "a blank value normalizes to an empty array" do
    assert_equal [], Admin::FieldParams.normalize(nil)
    assert_equal [], Admin::FieldParams.normalize("")
    assert_equal [], Admin::FieldParams.normalize({})
  end

  test "an already-ordered array passes through, converting each row to a plain hash" do
    result = Admin::FieldParams.normalize([ { "name" => "Ada" }, { "name" => "Grace" } ])
    assert_equal [ { "name" => "Ada" }, { "name" => "Grace" } ], result
  end

  test "an index-keyed hash sorts by its numeric key, not string order" do
    hash = { "10" => { "name" => "Tenth" }, "2" => { "name" => "Second" }, "0" => { "name" => "First" } }
    assert_equal [ { "name" => "First" }, { "name" => "Second" }, { "name" => "Tenth" } ], Admin::FieldParams.normalize(hash)
  end

  test "a gap left by a client-side remove doesn't break ordering or drop rows" do
    hash = { "0" => { "name" => "First" }, "2" => { "name" => "Third" } }
    assert_equal [ { "name" => "First" }, { "name" => "Third" } ], Admin::FieldParams.normalize(hash)
  end

  test "ActionController::Parameters rows are converted with to_unsafe_h, not left as Parameters" do
    row = ActionController::Parameters.new(name: "Ada")
    result = Admin::FieldParams.normalize({ "0" => row })
    assert_equal [ { "name" => "Ada" } ], result
    assert_not_kind_of ActionController::Parameters, result.first
  end
end
