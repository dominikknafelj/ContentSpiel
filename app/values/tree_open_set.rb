# WHICH BRANCHES OF A PAGE TREE A PERSON HAS OPENED OR FOLDED, read from the
# cookie `cs_tree_open` (`COOKIE`). The Pages tree draws its folds from it on the
# server from the first paint (`Admin::PagesScreen::TreeComponent`,
# `TreeRowComponent.for_page`); `to_s` is the hook for the mind graph's list,
# which does not read it yet. The browser writes it, through `tree/open_set.js` alone; no Ruby
# writes it (`admin_design_rules_test.rb`, "the open set has one writer").
#
# THE FORMAT. Page ids joined by `.`, the newest first: a bare id is a branch
# opened beyond the default, and `-` before an id a branch folded where the
# default would show it open (the root). Example: `12.40.-7`. The cookie
# holds nothing but page ids, and is sent on the admin path only, so a
# visitor's page never sees it.
#
# THE RULE (`open?`), one for the server, `open_set.js` and the graph:
# a page on the path to the selected page is open, whatever the cookie says,
# so a drawing never hides the selected row; else a folded entry folds it;
# else the root is open; else only an opened entry opens it. The path is a
# view state and is never stored: the scripts forget the folds on it as a
# page is opened (`forgetFolds`).
#
# WHAT IS READ is held to the viewer and to a size. A value that is not
# valid text, or is over `MAX_BYTES`, is read as nothing; entries past the
# first `LIMIT` set nothing; an entry that is not an id (or `-` and an id)
# is skipped, and so is an id the viewer cannot read (`readable_ids`: the readable pages, not the ancestors drawn only as a path): a
# cookie can't make a row appear, and a hand-written one only folds what the
# viewer has.
class TreeOpenSet
  COOKIE = "cs_tree_open"
  LIMIT = 300
  MAX_BYTES = 4_096

  ENTRY = /\A(-?)([1-9]\d{0,18})\z/

  # The set `raw` (the cookie's value, or nil) holds for the pages among
  # `readable_ids`.
  def self.parse(raw, readable_ids:)
    # A cookie is whatever the browser sends: bytes that are not text are
    # read as nothing before anything else looks at them.
    return EMPTY unless raw.is_a?(String) && raw.valid_encoding?
    return EMPTY if raw.blank? || raw.bytesize > MAX_BYTES

    readable = readable_ids.to_set
    seen = Set.new
    entries = raw.split(".").first(LIMIT).filter_map do |token|
      sign, digits = ENTRY.match(token)&.captures
      next unless digits

      id = digits.to_i
      next if !readable.include?(id) || !seen.add?(id)

      [ id, sign.empty? ? :opened : :folded ]
    end
    new(entries)
  end

  # `entries`: `[id, :opened | :folded]`, the newest first, one per id.
  def initialize(entries)
    @entries = entries.freeze
    @opened = entries.filter_map { |id, kind| id if kind == :opened }.to_set.freeze
    @folded = entries.filter_map { |id, kind| id if kind == :folded }.to_set.freeze
    freeze
  end

  # Is the branch of page `id` drawn open? `root:` the tree's root,
  # `on_path:` an ancestor of the selected page (the rule above).
  def open?(id, root:, on_path:)
    return true if on_path
    return false if @folded.include?(id)

    root || @opened.include?(id)
  end

  # The value as it was kept, in the cookie's format and order: what the
  # graph's list is to be handed (`data-tree-open`); nothing hands it yet.
  def to_s = @entries.map { |id, kind| kind == :folded ? "-#{id}" : id.to_s }.join(".")

  EMPTY = new([])
end
