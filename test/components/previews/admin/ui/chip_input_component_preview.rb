module Admin
  module Ui
    # `Admin::Ui::ChipInputComponent` (design pass round 2): tags with "Create tag",
    # related posts with a dot and a status hint, an empty field, and a chip the
    # server refused. Typing in the Lookbook reaches the real suggestion
    # endpoints only when signed in to CS Studio in the same browser.
    class ChipInputComponentPreview < ViewComponent::Preview
      def tags
        render Admin::Ui::ChipInputComponent.new(
          name: "post[tag_names][]", id: "preview-tags", label: "Tags", search_url: "/cs-studio/tags/suggest", create: true,
          chips: [ { value: "rails", label: "rails" }, { value: "ruby", label: "ruby" } ], placeholder: "Add a tag…",
          help: "Press Enter or a comma to add. New tags are created when you save."
        )
      end

      # One value, no creating: a post-list block's tag filter.
      def single_value
        render Admin::Ui::ChipInputComponent.new(
          name: "block[settings][tag]", id: "preview-single", label: "Tag", search_url: "/cs-studio/tags/suggest",
          chips: [ { value: "news", label: "news" } ], single: true, placeholder: "Any"
        )
      end

      def empty
        render Admin::Ui::ChipInputComponent.new(
          name: "post[tag_names][]", id: "preview-empty", label: "Tags", search_url: "/cs-studio/tags/suggest", create: true, placeholder: "Add a tag…"
        )
      end

      def related_posts
        render Admin::Ui::ChipInputComponent.new(
          name: "post[related_post_ids][]", id: "preview-related", label: "Related posts", search_url: "/cs-studio/link_targets?type=post", noun: "post",
          chips: [ { value: "1", label: "Hello world", dot: "bg-cat-1" }, { value: "2", label: "Shipping translations", hint: "Draft", dot: "bg-cat-2" },
                   { value: "3", label: "Launch day", hint: "Scheduled", dot: "border border-cat-3" } ],
          hidden_note: "+2 related posts you can’t open (kept)", placeholder: "Search posts to link…"
        )
      end

      def with_invalid_chip
        render Admin::Ui::ChipInputComponent.new(
          name: "post[tag_names][]", id: "preview-invalid", label: "Tags", search_url: "/cs-studio/tags/suggest", create: true,
          chips: [ { value: "rails", label: "rails" }, { value: "x" * 80, label: "x" * 80, invalid: true } ],
          errors: [ "The tag “#{'x' * 20}…” is too long." ]
        )
      end
    end
  end
end
