#!/usr/bin/env ruby
# frozen_string_literal: true

# Checks that splitting CLAUDE.md into a short rules file plus
# `docs/reference/*.md` lost nothing and copied nothing twice.
#
#   ruby script/check_claude_split.rb tmp/CLAUDE.before.md
#
# The argument is the whole CLAUDE.md as it was before the split (the split
# was made from a copy kept at `tmp/CLAUDE.before.md`, which is not committed:
# a checkout that no longer has it has nothing to check). Both sides are cut
# into sentences the same way, and every sentence of the old file must occur
# as many times across the new `CLAUDE.md` and `docs/reference/*.md` as it did
# before -- a sentence that is gone is "missing", one that now occurs more
# often is "duplicated". Whitespace is ignored. What the new files add on
# purpose (the index, the one-line rules, the pitfall labels, each reference
# file's "Describes" line) is listed in ADDED, so an unexpected sentence in
# the new files is reported too: it is either a missing entry here or text
# that should not be there. `docs/reference/i18n.md` is not part of the
# comparison: it was written on its own, before the split.
#
# How the text is cut. A line is a unit of its own (a list item, the label
# of a list, a paragraph); a heading line is structure and is ignored on both
# sides. Inside a line, a sentence ends at a full stop followed by a space,
# unless the stop is inside a code span, which is kept whole.
#
# Exit status 0 only when nothing is missing, duplicated or unexpected.

# Lines the split added, as they stand in the new files. A Regexp matches a
# whole sentence.
ADDED = [
  /\A> Describes: /,
  "This file keeps the rules a change can break without anything failing loudly, and the commands to run before you start.",
  "The descriptions of how each part works live in `docs/reference/`, one file per topic; they are long on purpose (they record the incidents behind the rules), so read the one that covers what you are about to change.",
  "Before changing the page tree, `public_paths`, the public router or the sitemap (`app/models/page.rb`, `app/models/public_site/`, `app/controllers/pages_controller.rb`, `config/routes.rb`, `config/sitemap.rb`), read `docs/reference/page-tree-and-routing.md`.",
  "Before changing content blocks, post content types or the block cards in the editor (`app/models/content_block.rb`, `app/models/content_types/`, `app/models/block_types/`), read `docs/reference/content-blocks-and-types.md`.",
  "Before changing CS Studio's shell, dashboard, audit log screen, ⌘K, system status, preview bar or mind graph (`app/controllers/admin/`, `app/components/admin/shell/`, `app/queries/dashboard/`, `app/queries/jump/`, `app/models/audit/sentence.rb`), read `docs/reference/cs-studio-shell-and-dashboard.md`.",
  "Before changing a shared admin component, a dialog, a toast, a form control, the theme or the Tags screen (`app/components/admin/`, `app/views/admin/`, `app/javascript/controllers/`), read `docs/reference/design-system.md`.",
  "Before changing autosave, a save footer, the leave guard, stale-save handling or anything that sends a write from the browser (`app/javascript/autosave/`, `Admin::AutosaveResponses`, `Admin::StaleForm`), read `docs/reference/save-rule-and-write-queue.md`.",
  "Before changing the page or post editor, the translation pair, the rich-text dialogs, the New page and New post dialogs or the posts list (`app/components/admin/editor_screen/`, `app/components/admin/posts_screen/`), read `docs/reference/editors-and-translation-pair.md`.",
  "Before changing Settings, the Languages card or the AI translation card (`app/controllers/admin/settings_controller.rb`, `app/services/settings/`, `app/services/locales/`), read `docs/reference/settings-languages-ai.md`.",
  "Before changing users, groups, the permission matrix or API tokens in CS Studio (`app/services/users/`, `app/services/groups/`, `app/services/api_tokens/`, `app/components/admin/users_screen/`, `groups_screen/`, `tokens_screen/`), read `docs/reference/users-groups-tokens.md`.",
  "Before changing authentication, a permission, a grant, a service's authorization or the audit log (`app/models/access_control/`, `app/models/audit/`, `app/services/application_service.rb`, `app/models/api_token.rb`), read `docs/reference/access-control-and-audit.md`.",
  "Before changing rich text, its renderer, its Markdown form, the vendored editor or the public render cache and content version (`app/models/rich_text/`, `config/importmap.rb`, `app/models/public_site.rb`), read `docs/reference/rich-text.md`.",
  "Before changing the media library, its uploads, usages, variants or picker (`app/models/media/`, `app/services/media/`, `app/components/admin/media_library/`, `app/components/media/`), read `docs/reference/media.md`.",
  "Before changing the trash, restoring, purging or retention (`app/services/trash/`, `app/models/concerns/trashable.rb`, `app/jobs/trash/`), read `docs/reference/trash.md`.",
  "Before changing translation tracking and status, the Translations matrix, AI translation or the encryption keys (`app/models/translations/`, `app/models/ai/`, `app/services/ai/`), read `docs/reference/translations.md`.",
  "Before adding or changing an admin string, a locale file or a date format (`config/locales/`, `Admin::AdminComponent`), read `docs/reference/i18n.md`.",
  "Each rule names the test that guards it where there is one; the reference file in the index explains the reasoning.",
  "Every public URL is a stored `public_paths` row derived by `PublicSite::Paths` from model callbacks: never write one by hand, never resolve a request by walking the tree, and keep `test/models/public_site/paths_test.rb` (parity with a full rebuild) green when a write path feeds a URL.",
  "Every content, settings, user, group and token write goes through an `ApplicationService` that calls `authorize!(` and `record_event(`, and a controller never writes a record itself (`test/services/service_contract_test.rb`, `test/services/service_behaviour_contract_test.rb`).",
  "A record outside the viewer's scope is not found, not forbidden: look it up through `AccessControl.scope` and answer 404, and use `AccessControl.holds?` for navigation only, never to gate a write.",
  "A permission or content type removed from its registry is dormant, not gone: a grant naming it matches nothing but is carried through every save until someone presses Remove, and a group is judged on its grants as stored (`LiveGrants#as_stored`).",
  "The owner flag changes only through `PATCH users/:id/owner`; the ordinary user form does not permit `owner`.",
  "`Audit.record` is the one write path of the append-only audit log, and no secret reaches a snapshot, a log line or a page: a password digest, a token's `lookup_digest`, an API key (`Audit::Snapshot::NEVER_STORED`, `filter_parameters`).",
  "A token or API key is never rendered, logged or audited after it is created.",
  "`Settings::Save` and `Locales::Enable`/`Disable`/`MakeDefault`/`Configure` lock the settings row first (`site.lock!`) and decide from the locked row.",
  "Trashed pages, posts and images are hidden explicitly at each narrowing point, never by a `default_scope`; a new list, search, picker or public query over them belongs in `test/integration/trash_visibility_test.rb`.",
  "`public_paths`, `media_usages` and `translation_states` are derived rows, refreshed inside the transaction of the write that changes them and never written by hand; a write path that changes what they are computed from belongs in `test/services/translation_state_parity_test.rb` or `test/models/public_site/paths_test.rb`.",
  "The public content version moves only through `PublicSite.bump_version!`; a write that goes around the callbacks (`update_all`, `update_columns`, `touch_all`, `insert_all`, `delete_all`) bumps it or says `# version: none (reason)` on the line (`test/lib/version_bump_test.rb`).",
  "No inline event handlers in a view, a component, a helper or a script's markup: wire behaviour through `data-action` (`test/lib/inline_handlers_test.rb`).",
  "CS Studio sources use tokens, not colour literals: no hex or `rgb()`/`hsl()` value, no `dark:` variant other than `dark:scheme-dark`, no `danger` in a translation chip or language tab, and no `mx-auto` in the shell except the 403 and 404 messages (`test/lib/admin_design_rules_test.rb`).",
  "Every autosave, block reorder, block form and tree move of a CS Studio screen is sent through `app/javascript/autosave/queue.js`, never from a hand-built request beside it, and an autosave carries the record's `base_updated_at` so a stale one is refused with a 409 and nothing is written.",
  "Content screens autosave; configuration screens (Settings, Groups, Users, Change password) save explicitly through `Admin::SaveBarComponent`.",
  "Choosing a library image for a hero or an image block goes through `Media::Choosing`, and the database's own foreign key is what keeps an image in use from being deleted.",
  "Each of these sits at the end of a description in `docs/reference/` and is repeated here because the mistake it names is easy to make.",
  "**Public URLs** (`docs/reference/page-tree-and-routing.md`):",
  "**Public routing** (same file):",
  "**The write queue** (`docs/reference/save-rule-and-write-queue.md`):",
  "**Import-map pins** (`docs/reference/rich-text.md`):",
  "**AI requests** (`docs/reference/translations.md`):",
  "**Active Record encryption keys** (same file):"
].freeze

ROOT = File.expand_path("..", __dir__)
NEW_FILES = ([ File.join(ROOT, "CLAUDE.md") ] + Dir[File.join(ROOT, "docs/reference/*.md")].sort)
  .reject { |path| File.basename(path) == "i18n.md" }

def sentences(text)
  text.lines.flat_map do |line|
    line = line.strip
    next [] if line.empty? || line.match?(/\A\#{1,6} /)

    line = line.sub(/\A[-*] /, "")
    spans = []
    masked = line.gsub(/`[^`]*`/) { |span| spans << span; "\u0000#{spans.size - 1}\u0000" }
    masked.split(/(?<=\.)\s+/).map do |piece|
      piece.gsub(/\u0000(\d+)\u0000/) { spans[Regexp.last_match(1).to_i] }
    end
  end
end

def key(sentence) = sentence.gsub(/\s+/, "")

def tally(list) = list.each_with_object(Hash.new(0)) { |sentence, counts| counts[key(sentence)] += 1 }

before_path = ARGV.first or abort "usage: ruby script/check_claude_split.rb tmp/CLAUDE.before.md"
before = sentences(File.read(before_path))
after = NEW_FILES.flat_map { |path| sentences(File.read(path)) }

wanted = tally(before)
found = tally(after)
shown = (before + after).each_with_object({}) { |sentence, by_key| by_key[key(sentence)] ||= sentence }
added = ADDED.select { |entry| entry.is_a?(String) }.flat_map { |entry| sentences(entry) }.map { |entry| key(entry) }
added_patterns = ADDED.grep(Regexp)
added_sentence = ->(sentence) { added.include?(key(sentence)) || added_patterns.any? { |pattern| sentence.match?(pattern) } }

missing = wanted.keys.select { |sentence| found[sentence] < wanted[sentence] }
duplicated = found.keys.select { |sentence| wanted.key?(sentence) && found[sentence] > wanted[sentence] }
unexpected = after.reject { |sentence| wanted.key?(key(sentence)) || added_sentence.(sentence) }.uniq

{ "missing" => missing, "duplicated" => duplicated }.each do |label, keys|
  keys.each { |entry| puts "#{label}: #{shown[entry][0, 140]}" }
end
unexpected.each { |sentence| puts "unexpected: #{sentence[0, 140]}" }

puts "#{wanted.values.sum} sentences checked: #{missing.size} missing, #{duplicated.size} duplicated, #{unexpected.size} unexpected"
exit(missing.empty? && duplicated.empty? && unexpected.empty? ? 0 : 1)
