require "test_helper"

# Public paths are built in exactly one place (spec §6.2). A locale prefix
# interpolated anywhere else is the drift this guards against.
class PublicUrlsGuardTest < ActiveSupport::TestCase
  ALLOWED = %w[app/models/public_site/urls.rb].freeze

  test "no hand-built locale prefixes outside PublicSite::Urls" do
    offenders = Dir.glob(Rails.root.join("{app,config}/**/*.{rb,erb}")).filter_map do |file|
      relative = file.delete_prefix("#{Rails.root}/")
      next if ALLOWED.include?(relative)

      relative if File.read(file).match?(%r{"/#\{\s*(locale|code|default_locale)\b})
    end
    assert_empty offenders
  end
end
