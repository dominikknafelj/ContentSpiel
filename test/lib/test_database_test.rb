require "test_helper"

# Each working folder has a test database of its own
# (lib/content_spiel/test_database.rb): two worktrees that shared one emptied
# each other's tables in the middle of a run.
class TestDatabaseTest < ActiveSupport::TestCase
  test "the main folder and CI's checkout use content_spiel_test, a worktree a name of its own" do
    assert_equal "content_spiel_test", ContentSpiel::TestDatabase.name_for("/src/ContentSpiel")
    assert_equal "content_spiel_test_note", ContentSpiel::TestDatabase.name_for("/src/ContentSpiel-note")
    assert_equal "content_spiel_test_mind_graph", ContentSpiel::TestDatabase.name_for(Pathname.new("/src/ContentSpiel-Mind.Graph"))
  end

  test "this run uses the database named after its own folder, or a worker's copy of it" do
    expected = ContentSpiel::TestDatabase.name_for(Rails.root)
    actual = ActiveRecord::Base.connection_db_config.database
    assert actual == expected || actual.start_with?("#{expected}-"), "#{actual} is not #{expected}"
  end
end
