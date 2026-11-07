module Admin
  module Shell
    # What the tree column holds, by the name a screen gives it with
    # `content_for :tree_label` (`Admin::ShellHelper#admin_tree_subject`;
    # "pages" when a screen gives none). The subject picks the words of
    # everything the shell draws for the column: the fold buttons, the
    # divider and the top bar's button, under
    # `admin.components.shell.tree_subject.<subject>` (shell.en.yml), so a
    # screen hands over a name and never its own words. `fill:` says the
    # column's content fills it from top to bottom (`.admin-shell__tree--fill`):
    # the mind graph's list, whose region takes what the head and the find
    # field leave. The Pages tree is as tall as its rows.
    #
    # An unknown subject raises: a misspelt name would otherwise draw a
    # column whose buttons read a key that is not there.
    module TreeSubjects
      ALL = {
        "pages" => { fill: false },
        "mind_graph" => { fill: true }
      }.freeze

      # The words a subject has, one key each under its family.
      WORDS = %i[hide show open button divider divider_tooltip].freeze

      # The subject's settings, or `KeyError` for a name that is not one.
      def self.fetch(name)
        return ALL.fetch(name.to_s) if ALL.key?(name.to_s)

        raise KeyError, "unknown tree subject #{name.inspect}: one of #{ALL.keys.join(', ')}"
      end

      def self.fill?(name) = fetch(name).fetch(:fill)

      # The key of one of a subject's words, relative to `admin` as a
      # script's `data-messages` names it (`Admin::MessagesHelper`).
      def self.key(name, word)
        fetch(name)
        raise KeyError, "a tree subject has no word #{word.inspect}: one of #{WORDS.join(', ')}" unless WORDS.include?(word)

        "components.shell.tree_subject.#{name}.#{word}"
      end
    end
  end
end
