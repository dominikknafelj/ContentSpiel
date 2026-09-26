# The pages and sample posts the setup wizard (and Avo's "Create starter
# pages" action) can add, written in one locale -- the site's default at the
# time. Every method is idempotent: it looks records up first, through
# Mobility's `.i18n` scope, because translated columns are jsonb and a plain
# `where(slug: ...)` would never match (see db/seeds.rb).
#
# That lookup spans every configured locale (`find_in_any_locale`), not just
# the one being written: an admin who ran this in one locale and later
# changes the site's default locale, or clicks "Create starter pages" again
# after that, must not get duplicate section pages/posts/blocks just because
# this locale's slug/title translation happens to be blank -- a page or post
# that already exists in *any* locale still counts. Creation itself still
# happens in the given locale only.
module StarterContent
  WELCOME_HTML = "<p>Welcome to your new site. Sign in to the admin to edit this page.</p>".freeze

  SECTIONS = [
    { slug: "blog", title: "Blog", content_type: "blog",
      post: { title: "Hello, world", excerpt: "The first post on this site.",
              body: "<p>This is a sample blog post. Edit or delete it in the admin.</p>" } },
    { slug: "resume", title: "Resume", content_type: "resume_entry",
      post: { title: "Your first role", body: "<p>Describe what you did in this role.</p>",
              metadata: { "company" => "Example Co", "role_type" => "ic", "start_date" => "2024-01-01", "end_date" => "" } } },
    { slug: "now", title: "Now", content_type: "now_update",
      post: { title: "What I'm doing now", body: "<p>Share what you're focused on at the moment.</p>" } }
  ].freeze

  module_function

  # Always run when setup finishes, so "/" is never a 404 on a new site.
  def ensure_home!(locale:)
    Mobility.with_locale(locale) do
      home = Page.find_by(parent_id: nil) ||
        Page.create!(page_type: :standard, title: "Home", slug: "", published_at: Time.current)
      home.content_blocks.create!(block_type: :rich_text, position: 0, body: WELCOME_HTML) if home.content_blocks.none?
      home
    end
  end

  def create_pages_and_posts!(locale:)
    home = ensure_home!(locale: locale)

    Mobility.with_locale(locale) do
      SECTIONS.each do |section|
        find_or_create_section_page!(home, section)
        find_or_create_sample_post!(section)
      end
    end
  end

  # `locale:` is kept for interface compatibility with the other methods
  # (callers pass it), but the lookup below already checks every locale, so
  # it goes unused here.
  def added?(locale:)
    home = Page.find_by(parent_id: nil)
    return false unless home

    SECTIONS.all? { |section| find_section_page(home, section).present? }
  end

  def find_or_create_section_page!(home, section)
    find_section_page(home, section) ||
      Page.create!(parent: home, page_type: :standard, title: section[:title], slug: section[:slug],
        published_at: Time.current).tap do |page|
        page.content_blocks.create!(block_type: :post_list, position: 0,
          settings: { "content_type" => section[:content_type] })
      end
  end

  def find_or_create_sample_post!(section)
    attributes = section[:post]
    find_sample_post(section) ||
      Post.create!(content_type: section[:content_type], published_at: Time.current, **attributes)
  end

  def find_section_page(home, section)
    find_in_any_locale { Page.i18n.where(slug: section[:slug]).where(parent_id: home.id).first }
  end

  def find_sample_post(section)
    title = section[:post][:title]
    find_in_any_locale { Post.i18n.where(title: title).where(content_type: section[:content_type]).first }
  end

  # Runs `block` once per configured locale, inside that locale, and returns
  # the first match -- so a record found by its translation in any locale is
  # treated as "already exists", the same record `create_pages_and_posts!`
  # would otherwise create a duplicate of under the locale it's writing.
  def find_in_any_locale
    Mobility.available_locales.each do |locale|
      match = Mobility.with_locale(locale) { yield }
      return match if match
    end
    nil
  end
end
