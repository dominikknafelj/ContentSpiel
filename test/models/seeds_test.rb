require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  test "seeding is idempotent and creates exactly one dev admin" do
    original_env = Rails.env

    begin
      # Mock Rails.env to return development
      development_env = ActiveSupport::StringInquirer.new("development")
      Rails.singleton_class.alias_method :_original_env, :env
      Rails.singleton_class.define_method(:env) { development_env }

      assert_difference "User.count", 1 do
        load Rails.root.join("db/seeds.rb")
      end

      assert_no_difference "User.count" do
        load Rails.root.join("db/seeds.rb")
      end
    ensure
      Rails.singleton_class.remove_method :env
      Rails.singleton_class.alias_method :env, :_original_env
      Rails.singleton_class.remove_method :_original_env
    end
  end

  test "seeding does nothing outside development" do
    begin
      # Mock Rails.env to return test
      test_env = ActiveSupport::StringInquirer.new("test")
      Rails.singleton_class.alias_method :_original_env, :env
      Rails.singleton_class.define_method(:env) { test_env }

      assert_no_difference "User.count" do
        load Rails.root.join("db/seeds.rb")
      end
    ensure
      Rails.singleton_class.remove_method :env
      Rails.singleton_class.alias_method :env, :_original_env
      Rails.singleton_class.remove_method :_original_env
    end
  end
end
