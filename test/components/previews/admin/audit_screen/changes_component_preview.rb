module Admin
  module AuditScreen
    # An event's field changes: word diffs per language, a body that only has
    # digests ("Changed"), a flag, and text too long to diff.
    class ChangesComponentPreview < ViewComponent::Preview
      def two_languages
        render Admin::AuditScreen::ChangesComponent.new(field_changes: {
          "en title" => [ "Welcome to the new site", "Welcome to our new site" ],
          "de title" => [ "Willkommen", "Willkommen auf der neuen Seite" ], "de excerpt" => [ nil, "Alles neu gebaut." ]
        })
      end

      def body_flag_and_list
        render Admin::AuditScreen::ChangesComponent.new(field_changes: {
          "en body" => { "digest_before" => "a1", "digest_after" => "b2" }, "published" => [ false, true ], "tag_ids" => [ [ 1 ], [ 1, 2 ] ]
        })
      end

      def too_long
        render Admin::AuditScreen::ChangesComponent.new(field_changes: { "en excerpt" => [ "alpha " * 5_000, "beta " * 5_000 ] })
      end

      def nothing = render(Admin::AuditScreen::ChangesComponent.new(field_changes: {}))
    end
  end
end
