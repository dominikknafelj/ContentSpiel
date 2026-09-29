require "test_helper"

class ApplicationServiceTest < ActiveSupport::TestCase
  # A minimal concrete service, just to reach the private `failure` helper
  # the way a real subclass would -- exercising `ApplicationService::Result`
  # directly wouldn't prove `failure(record)`'s default-argument behaviour.
  class NoOpService < ApplicationService
    def initialize(record) = @record = record
    def call = failure(@record)
  end

  test "a failure with no error messages still reads as not ok, with a generic message" do
    result = NoOpService.call(Post.new)

    assert_not result.ok?
    assert_equal [ "Post could not be saved" ], result.errors
  end

  test "a failure for a nil record gets a generic message with no model name" do
    result = ApplicationService::Result.failure(nil)

    assert_not result.ok?
    assert_equal [ "The change could not be saved" ], result.errors
  end

  test "a failure with real error messages keeps them, not the generic fallback" do
    result = ApplicationService::Result.failure(nil, [ "Title can't be blank" ])

    assert_not result.ok?
    assert_equal [ "Title can't be blank" ], result.errors
  end

  # CS Studio answers a permission refusal with 403 and anything else with
  # 422 (access-control design spec §3.4), so the Result has to say which.
  test "a permission refusal is denied; a validation failure and a success aren't" do
    theirs = create_post(title: "Theirs")
    denial = as(users(:reader)) { Posts::Save.call(theirs, attributes: { published: false }) }
    assert denial.denied?
    assert_not denial.ok?

    assert_not ApplicationService::Result.failure(nil, [ "Title can't be blank" ]).denied?
    assert_not ApplicationService::Result.success(nil).denied?
  end
end
