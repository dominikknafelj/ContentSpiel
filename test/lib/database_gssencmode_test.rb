require "test_helper"

# libpq on macOS tries GSSAPI encryption before it connects, through
# Kerberos, which is not safe after a fork: a parallel test run's worker
# could crash in the pg gem and the run hang forever. The development and
# test entries turn the negotiation off (`gssencmode: disable`; the local
# Postgres offers no GSSAPI), so no command needs `PGGSSENCMODE=disable`
# typed in front of it. Production is left to its host's libpq settings.
class DatabaseGssencmodeTest < ActiveSupport::TestCase
  test "the development and test databases are reached without GSSAPI encryption" do
    %w[development test].each do |env|
      config = ActiveRecord::Base.configurations.configs_for(env_name: env, name: "primary")
      assert_equal "disable", config.configuration_hash[:gssencmode].to_s, "config/database.yml's #{env} entry"
    end
  end

  test "the test run's own connection says so" do
    assert_equal "disable", ActiveRecord::Base.connection.raw_connection.conninfo_hash[:gssencmode]
  end
end
