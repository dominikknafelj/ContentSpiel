module Admin
  module Ui
    # The del/ins word-diff style shared by the translation reference card and the audit event page.
    class WordDiffComponentPreview < ViewComponent::Preview
      def changed_word = render(Admin::Ui::WordDiffComponent.new(segments: [ [ :equal, "Welcome to " ], [ :delete, "the" ], [ :insert, "our" ], [ :equal, " new site" ] ]))
    end
  end
end
