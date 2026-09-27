# The setup wizard's optional "Starter content" step, available later from
# the Pages index (design spec 2026-09-26 §5). Idempotent -- existing pages
# and posts are left alone.
class Avo::Actions::CreateStarterPages < Avo::BaseAction
  self.name = "Create starter pages"
  self.standalone = true
  self.message = "Adds Blog, Resume and Now pages (each listing its posts) and one sample post per type, " \
    "in the site's default language. Anything that already exists is left alone."

  def handle(**args)
    StarterContent.create_pages_and_posts!(locale: Current.site.default_locale)
    succeed("Starter pages are ready.")
  end
end
