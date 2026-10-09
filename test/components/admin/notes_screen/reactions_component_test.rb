require "test_helper"

# A reaction chip's name for a screen reader says the emoji in words. The
# words are a list in the locale file, in the order of `Notes::EMOJI`: an emoji
# added to the set without its name, or a list out of step, fails here.
class Admin::NotesScreen::ReactionsComponentTest < ActiveSupport::TestCase
  test "every emoji of the set has its own name, in the set's order" do
    names = I18n.t("admin.components.notes_screen.reactions.names")

    assert_kind_of Array, names
    assert_equal Notes::EMOJI.size, names.size
    assert names.all? { |name| name.is_a?(String) && name.match?(/\A[a-z][a-z ]+\z/) }, names.inspect
    assert_equal names, names.uniq
    assert_equal [ "thumbs up", "party popper", "waving hand" ], names.values_at(Notes::EMOJI.index("👍"), Notes::EMOJI.index("🎉"), Notes::EMOJI.index("👋"))
  end
end
