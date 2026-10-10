# Rewrites Stimulus identifiers after a controller moved. Usage:
#   ruby script/layout/identifiers.rb admin--notes-live=admin--notes--live admin--dialog=admin--ui--dialog
# Idempotent. Deleted in the plan's last task (with test/lib/layout_tools_test.rb).
#
# Three spellings of an identifier are rewritten, each by the longest old identifier it
# equals or extends:
#   admin--notes-live-target          markup, JS, CSS selectors, "admin--notes-live:event"
#   data-admin--notes-live-id-param   the same after "data-" (a target, value, param, class)
#   admin__notes_live_id_param        a Ruby hash key (`data: { admin__notes_live_id_param: }`)
require "pathname"

module LayoutIdentifiers
  # Every identifier that was ever one-level (the 55 controllers loose in
  # app/javascript/controllers/admin at the start of the cleanup, `git ls-tree main`), so
  # a leftover of an earlier move is not taken for its shorter sibling.
  ORIGINAL = %w[
    admin--ai-settings admin--auto-submit admin--autosave admin--blocks admin--branch-picker
    admin--bulk-select admin--busy admin--char-count admin--chip-input admin--clipboard
    admin--command-palette admin--dialog admin--drawer admin--file-drop-guard admin--fragment-links
    admin--group-hint admin--groups admin--media-drop admin--media-field admin--media-panel
    admin--media-picker admin--media-select admin--media-upload admin--menu admin--mind-graph
    admin--new-record admin--note-composer admin--note-gif admin--note-reactions admin--note-refusal
    admin--note-unsaved admin--notes-alert admin--notes admin--notes-live admin--notes-permission
    admin--override-field admin--password-answer admin--password-disclosure admin--pending-lock
    admin--permission-matrix admin--queue-hold admin--quick-create admin--repeat-rows admin--rich-text
    admin--rich-text-dialog admin--save-bar admin--section admin--settings-tabs admin--slug-preview
    admin--sortable-rows admin--tag-dialogs admin--toast admin--token-reveal admin--translate
    admin--tree
  ].freeze

  # A run of the old one-level form, matched whole (the atomic group forbids a shorter match).
  # May follow "data-" or any character outside [a-z0-9-]. A run followed by "--" is already
  # in the new form; one followed by "_" is a mixed spelling (reported, never guessed).
  HYPHEN = /(?:(?<=data-)|(?<![a-z0-9-]))(?>admin--[a-z0-9]+(?:-[a-z0-9]+)*)(?!--)(?!_)/
  MIXED = /(?:(?<=data-)|(?<![a-z0-9-]))admin--[a-z0-9]+(?:-[a-z0-9]+)*_[a-z0-9]/
  UNDERSCORE = /(?<![A-Za-z0-9_])(?>admin__[a-z0-9]+(?:_[a-z0-9]+)*)(?!__)/

  def self.line_of(text, offset) = text[0...offset].count("\n") + 1

  # Returns [new text, review lines]. +label+ names the file in the review lines.
  def self.rewrite(text, pairs, label)
    review = []
    known = (ORIGINAL | pairs.keys)
    swap = lambda do |token, hyphen_token, to_underscore|
      owners = known.select { |id| hyphen_token == id || hyphen_token.start_with?("#{id}-") }
      owner = owners.max_by(&:length)
      line = "#{label}:#{line_of(text, $~.begin(0))}: #{token}"
      unless owner && pairs.key?(owner)
        review << "#{line} (leftover of an earlier move?)" if owner && owners.any? { |id| pairs.key?(id) }
        next token
      end
      review << "#{line} (could also be #{(owners - [ owner ]).join(', ')})" if owners.size > 1
      new = pairs.fetch(owner)
      new = new.tr("-", "_") if to_underscore
      old = to_underscore ? owner.tr("-", "_") : owner
      new + token.delete_prefix(old)
    end

    changed = text.gsub(HYPHEN) { |token| swap.call(token, token, false) }
    changed = changed.gsub(UNDERSCORE) { |token| swap.call(token, token.tr("_", "-"), true) }
    text.scan(MIXED) { review << "#{label}:#{line_of(text, $~.begin(0))}: #{$~[0]} (mixed spelling, left alone)" }
    [ changed, review ]
  end

  def self.run(argv)
    pairs = argv.to_h { |arg| arg.split("=", 2) }
    abort "usage: identifiers.rb OLD=NEW ..." if pairs.empty? || pairs.any? { |old, new| new.nil? || old.empty? }

    root = Pathname(__dir__).join("../..").expand_path
    files = Dir[root.join("{app,test,docs,config/locales}/**/*.{rb,erb,js,css,yml,md}")] + [ root.join("CLAUDE.md").to_s ]
    # Specs, plans and product/architecture notes are dated records and quote old names on
    # purpose; built CSS is git-ignored; the guard and tool tests hold sample strings.
    excluded = %w[docs/superpowers docs/product docs/architecture app/assets/builds
                  test/lib/source_layout_test.rb test/lib/layout_tools_test.rb].map { |path| root.join(path).to_s }
    files.reject! { |path| excluded.any? { |prefix| path == prefix || path.start_with?("#{prefix}/") } }

    review = []
    files.each do |path|
      text = File.read(path)
      changed, lines = rewrite(text, pairs, Pathname(path).relative_path_from(root))
      review.concat(lines)
      next if changed == text

      File.write(path, changed)
      puts Pathname(path).relative_path_from(root)
    end
    puts "REVIEW:", review.uniq
  end
end

LayoutIdentifiers.run(ARGV) if $PROGRAM_NAME == __FILE__
