require "test_helper"

class BackupImageTest < ActiveSupport::TestCase
  test "the image installs restic and a pg_dump no older than the template's Postgres" do
    dockerfile = Rails.root.join("Dockerfile").read
    install = dockerfile[/apt-get install[^\n]*(?:\\\n[^\n]*)*/]
    assert_match(/\brestic\b/, install)
    client = install[/postgresql-client-(\d+)/, 1]
    assert client, "the Dockerfile names postgresql-client without its major version"
    template = Rails.root.join("lib/site_template/config/deploy.yml.tt").read[/image: postgres:(\d+)/, 1]
    assert template, "lib/site_template/config/deploy.yml.tt names no image: postgres:NN"
    assert_operator client.to_i, :>=, template.to_i
  end
end
