module Admin
  module ShellHelper
    # What the screen's tree column holds: the name a screen gives with
    # `content_for :tree_label`, or "pages" when it gives none. Read through
    # `Admin::Shell::TreeSubjects.fetch`, so a name that is not a subject
    # raises here, before the shell draws a part in words that do not exist.
    def admin_tree_subject
      name = content_for(:tree_label).presence&.then { |label| String.new(label) } || "pages"
      Admin::Shell::TreeSubjects.fetch(name)
      name
    end
  end
end
