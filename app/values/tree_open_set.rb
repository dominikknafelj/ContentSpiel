# WHICH BRANCHES OF A PAGE TREE A PERSON HAS OPENED OR FOLDED, read from the
# cookie `cs_tree_open` (`COOKIE`). The Pages tree draws its folds from it on the
# server from the first paint (`Admin::PagesScreen::TreeComponent`,
# `TreeRowComponent.for_page`), and the mind graph's list draws its first
# folds from `to_s`, handed over as `data-tree-open`. The browser writes it,
# through `tree/open_set.js` alone; no Ruby
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
    readable = readable_ids.to_set
    seen = Set.new
    new(tokens(raw).filter_map { |sign, id| [ id, sign.empty? ? :opened : :folded ] if readable.include?(id) && seen.add?(id) })
  end

  # The page ids `raw` names, read as `parse` reads them but against no
  # viewer: what a caller narrows to the readable ones before `parse`, so
  # it asks the database about these few and not about every page.
  def self.candidate_ids(raw) = tokens(raw).map(&:last).uniq

  # `[sign, id]` of each well-formed entry among the first `LIMIT`. A cookie
  # is whatever the browser sends: bytes that are not text are read as
  # nothing before anything else looks at them.
  def self.tokens(raw)
    return [] unless raw.is_a?(String) && raw.valid_encoding?
    return [] if raw.blank? || raw.bytesize > MAX_BYTES

    raw.split(".").first(LIMIT).filter_map do |token|
      sign, digits = ENTRY.match(token)&.captures
      [ sign, digits.to_i ] if digits
    end
  end
  private_class_method :tokens

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
  # graph's list is handed (`data-tree-open`).
  def to_s = @entries.map { |id, kind| kind == :folded ? "-#{id}" : id.to_s }.join(".")

  EMPTY = new([])
end
