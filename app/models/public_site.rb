# A fingerprint of everything a public page can show (spec §6.4; technical
# cleanup spec §4.8). Site-wide rather than per record: a page renders the
# nav, its listings and the footer, so a title change on *any* live page, a
# new post or a settings edit must invalidate every cached page. It is the
# public ETag (`PagesController#show`) and part of the rich-text render cache
# key (`RichText::Document#to_html`): a rendered body bakes in its internal
# links' hrefs and its images' URLs and `srcset`, none of which change the
# document's own digest.
#
# Two parts:
#
# 1. A stored counter (`PublicSite::Version`, one row), moved by
#    `bump_version!` when -- and only when -- published output can have
#    changed. An autosave of a draft moves nothing, so the public cache
#    survives editing.
# 2. The newest `published_at` that has already passed, of kept pages and of
#    kept posts. A scheduled page or post goes live at a moment no row is
#    written at, so no bump can mark it; but a publication time that passes
#    between two requests is by then the newest one that has passed, and the
#    second request reads a different value. Two indexed lookups.
#
# WHO BUMPS. The rule is conservative: a change that could be seen bumps,
# and so does one where telling is not cheap. A bump too many costs cache; a
# bump too few serves stale pages and answers 304 for them until something
# else bumps.
# - `Page`, `Post` (`Publishable#bump_public_version_when_live`): every
#   commit of a record whose own `published_at` is in the past before or
#   after the change -- an edit, publish, unpublish, trash, restore, purge,
#   and a `touch` (which is how a block write and a tag-only change reach
#   their page or post). Whatever its ancestors' state and whether or not it
#   is in the trash: more bumps than strictly needed, never fewer.
# - `ContentBlock`: every commit of a block whose owner is live.
# - `public_paths`: `PublicSite::Paths.write_all`, when it wrote a row of a
#   live record (the table has no callbacks; see there for why a draft's rows
#   don't count), `rebuild!`, and `Locales::Disable`.
# - `Media::Asset`: every commit, used or not (whether a live page shows an
#   image is a lookup across heroes, blocks and bodies); and every
#   `ActiveStorage::VariantRecord` commit (`config/initializers/
#   public_site_version.rb`), since a processed variant changes an `<img>`'s
#   `srcset` with no asset row changing.
# - `SiteSetting`: every commit (title, tagline, languages, the default
#   language, social links, the logo -- an attachment touches its record).
# - `Tag`: a rename or a delete; `PostTag`: a join row of a live post.
# - The services that write those tables around the callbacks
#   (`update_all`, `update_columns`, `touch_all`, `insert_all`,
#   `delete_all`) call `bump_version!` themselves.
#   `test/lib/version_bump_test.rb` fails on such a write in a file that
#   neither bumps nor says `# version: none (reason)` on the line.
# `test/models/public_site/version_test.rb` lists every write path with
# whether it moves the counter; a new one belongs in it.
#
# NOT COVERED, by design: a write made around the models and the services
# (the console's `update_columns`, raw SQL, a restored backup). `bin/rails
# public_site:bump_version` is for those. A restored backup needs more than
# the bump: it REWINDS the counter, so the values that follow were already
# used, and a render or an ETag made under one of them before the restore
# would be served for the restored content. Clear the cache too
# (`Rails.cache.clear`); a browser's or a CDN's stored ETag can still match
# until the counter has passed the value it had before the restore.
module PublicSite
  module_function

  # Four queries: the counter, the two publication times and the newest copy
  # in force. The last follows copies by the clock: a copy with a time of its
  # own (a change scheduled for later) bumps nothing when it is taken, and
  # comes into force when that time passes, with no write, so the version
  # must change then and not before. It is read from the copies, not from a
  # job having run (`settled_at`), so a request a second after the time gets
  # the new version. A scheduled RECORD's copy is in force at once and shown
  # from the record's `published_at`, which the second and third parts already
  # follow. Served by `index_published_versions_on_live_at`.
  def content_version
    [
      PublicSite::Version.current,
      Page.kept.published.maximum(:published_at),
      Post.kept.published.maximum(:published_at),
      Publishing::Version.in_force.maximum(:live_at)
    ].map { |value| value.is_a?(Integer) ? value : value&.to_f }.join("-")
  end

  # `content_version`, computed at most once per request (or job, or MCP
  # call): a single page render reaches for it once for its ETag plus once
  # per rich-text body it renders (`RichText::RenderContext`, in preview and
  # CS Studio too). Memoised on `Current`, which Rails resets around every
  # request and job, and which `bump_version!` clears -- so a render that
  # follows a committed write in the same request reads the new version.
  # Outside the executor (a bare `bin/rails runner` script) `Current` is
  # never reset, so a long-running script keeps its value until it bumps --
  # acceptable for scripts, which don't serve pages.
  def current_content_version
    Current.content_version ||= content_version
  end

  # Moves the counter: one atomic statement, `INSERT ... ON CONFLICT (id) DO
  # UPDATE SET counter = counter + 1` (`PublicSite::Version.bump!`), so the
  # first bump of a database without the row counts like every later one.
  #
  # After the commit of whatever transaction is open *when it is called*
  # (`ActiveRecord.after_all_transactions_commit`, the same deferral
  # `PublicSite::Paths.announce` uses); with none open it bumps at once. A
  # model's `after_commit` has none open; a service calling this next to an
  # `update_all`, or a sync running inside another record's `after_save`,
  # is deferred. So:
  # - a rolled-back write bumps nothing;
  # - the counter row is never locked for the length of a save, and two
  #   saves can't deadlock on it;
  # - a reader can't see the new counter before the rows it stands for --
  #   PROVIDED the caller bumps from inside the transaction that writes
  #   them, or after it has committed. A bump called with no transaction
  #   open and *followed* by the write moves the counter first: a page
  #   rendered in between is cached under the new version with the old
  #   rows, and nothing bumps again. So every explicit call sits inside its
  #   write's transaction (`PublicSite::Paths.write_all` opens its own for
  #   that reason). The other order is harmless: a page rendered between a
  #   commit and its bump is cached under the old version, which the bump
  #   then retires.
  #
  # A bump can still be lost one way: an `after_commit` callback that raises
  # stops the callbacks queued behind it, a deferred bump among them, after
  # the data has committed. `bin/rails public_site:bump_version` is the
  # remedy.
  #
  # One bump per call, not one per transaction: a branch purge bumps once
  # per live page. Each is a single-row update; de-duplicating them would
  # need state that survives a rollback correctly, and a lost bump is the
  # one failure this must not have.
  def bump_version!
    ActiveRecord.after_all_transactions_commit do
      PublicSite::Version.bump!
      Current.content_version = nil
    end
    nil
  end
end
