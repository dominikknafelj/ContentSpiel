module Admin
  # `Admin::TagInputComponent` (cs-studio spec §5.2): empty, and with a
  # value already naming a couple of existing tags (so the `<datalist>` has
  # something else to offer besides them).
  class TagInputComponentPreview < ViewComponent::Preview
    def empty
      render Admin::TagInputComponent.new(value: "")
    end

    def with_existing_tags
      Tag.find_or_create_by!(name: "rails")
      Tag.find_or_create_by!(name: "ruby")
      Tag.find_or_create_by!(name: "elixir")
      render Admin::TagInputComponent.new(value: "ruby, rails")
    end
  end
end
