require "test_helper"

# The half of "every registered type answers every question" that is CS
# Studio's: a type's input and its read-only display are its
# `Admin::Fields::<Type>Field`, found by name, because the type itself
# (`ContentModel::FieldType`) names no component.
class Admin::Fields::FieldTypesStudioTest < ActiveSupport::TestCase
  test "every registered type has its input in Admin::Fields and a read-only display" do
    ContentModel::FieldTypes.names.each do |name|
      input = "Admin::Fields::#{name.to_s.camelize}Field".safe_constantize

      assert input, "#{name} has no Admin::Fields::#{name.to_s.camelize}Field"
      assert_operator input, :<, Admin::Fields::Base, "#{name}'s input is a field input"
      assert_respond_to input, :display, "#{name}'s input says how its value reads where it can't be edited"
    end
  end
end
