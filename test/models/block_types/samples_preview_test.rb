require "test_helper"

# A shared check (block types spec, decision 14) for the tile's preview: every
# type that declares one, an outside type's included, draws something its own
# sample put in, so a preview that reads the wrong field is red from the day
# it is written.
class BlockTypes::SamplesPreviewTest < ActiveSupport::TestCase
  include EveryBlockType

  test "every type with a preview shows one of its sample's values" do
    with_every_type do
      types = BlockTypes.all.select(&:preview)
      assert_operator types.size, :>=, 5
      types.each { |definition| assert_preview_shows_a_sample_value(definition.name) }
    end
  end
end
