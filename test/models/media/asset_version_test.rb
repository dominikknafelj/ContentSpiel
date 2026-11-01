require "test_helper"

# The content version moves for an image only when a live page can show it
# (`Media::Asset#shown_publicly?`), and once per generation.
class Media::AssetVersionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def version = PublicSite::Version.current

  def upload(filename = "wide.png")
    asset = nil
    perform_enqueued_jobs(only: ActiveStorage::AnalyzeJob) { asset = create_media_asset(filename: filename) }
    clear_enqueued_jobs
    asset
  end

  def live_page_with(asset)
    page = create_page(title: "Live")
    page.update!(hero_media_asset: asset)
    publish_changes(page)
    page
  end

  test "an upload, its decode and its job move the version not at all while no page uses the image" do
    before = version
    asset = nil
    perform_enqueued_jobs { asset = create_media_asset(filename: "wide.png") }

    assert asset.reload.made?
    assert_equal before, version
  end

  test "an alt edit of an image only a draft uses moves nothing; of one a live page uses, once" do
    asset = upload
    draft = create_page(title: "Draft", published: false)
    draft.update!(hero_media_asset: asset)
    before = version
    asset.update!(alt: { "en" => "A draft's picture" })
    assert_equal before, version

    live_page_with(asset)
    before = version
    asset.update!(alt: { "en" => "A live picture" })
    assert_equal before + 1, version
  end

  test "a generation of an image a scheduled post's copy shows moves the version once, not once per width" do
    asset = upload
    post = create_post(title: "Later", published: false)
    post.assign_body(rich_doc(%(::image{asset="#{asset.id}"})), locale: "en")
    post.save!
    result = Posts::Save.call(post, attributes: { published: true, published_at: 1.day.from_now }, translations: {})
    assert result.ok?, result.errors.to_sentence
    assert Media::Usage.where(media_asset_id: asset.id, role: "published").exists?

    before = version
    perform_enqueued_jobs { Media::RenditionJob.perform_later(asset) }

    assert asset.reload.made?
    assert_operator asset.generation.files.size, :>, 1
    assert_equal before + 1, version
  end

  test "an image a live page's block shows moves it, through the block alone: a live page with no copy" do
    asset = upload
    page = create_page(title: "Blocks")
    block = ContentBlock.create!(owner: page, block_type: :image, position: 0, media_asset: asset)
    Publishing::Version.of(page).delete_all
    Media::Usage.where(media_asset_id: asset.id).delete_all
    Media::UsageIndex.refresh(block)

    usages = Media::Usage.where(media_asset_id: asset.id)
    assert_equal [ "block_image" ], usages.pluck(:role)
    assert usages.shown_publicly.exists?
    before = version
    asset.update!(alt: { "en" => "Block picture" })
    assert_equal before + 1, version

    page.update_columns(published_at: nil) # version: none (a test)
    assert_not asset.shown_publicly?
  end

  test "an image only a trashed page uses is not shown" do
    asset = upload
    page = live_page_with(asset)
    assert asset.shown_publicly?
    page.update_columns(trashed_at: Time.current) # version: none (a test)

    assert_not asset.shown_publicly?
  end

  test "a job that fails after writing the size and preview still moves the version for a live image" do
    asset = upload
    live_page_with(asset)
    asset.update_columns(preview: nil, width: nil, height: nil) # version: none (a row from before previews)
    before = version
    with_singleton_override(asset, :made_with?, ->(_fingerprint) { raise "boom" }) do
      assert_raises(RuntimeError) { Media::RenditionJob.new.perform(asset) }
    end

    assert asset.reload.preview.present?
    assert_equal before + 1, version
  end

  test "when the question raises the asset bumps" do
    asset = upload
    before = version
    with_singleton_override(Media::Usage, :shown_publicly, -> { raise "boom" }) do
      asset.update!(alt: { "en" => "Whatever" })
    end
    assert_equal before + 1, version
  end

  test "publishing a page whose image is still being made, then the job: the version moved after both" do
    asset = create_media_asset(filename: "wide.png")
    clear_enqueued_jobs
    page = create_page(title: "Early")
    page.update!(hero_media_asset: asset)
    before = version
    publish_changes(page)
    after_publish = version
    assert_operator after_publish, :>, before

    perform_enqueued_jobs { Media::RenditionJob.perform_later(asset) }
    assert_operator version, :>, after_publish
    assert asset.reload.made?
  end

  test "the job, then publishing a page that uses the image: the version moved after both" do
    asset = upload
    page = create_page(title: "Late")
    page.update!(hero_media_asset: asset)
    before = version
    perform_enqueued_jobs { Media::RenditionJob.perform_later(asset) }
    assert_equal before, version, "no live page shows it yet"

    publish_changes(page)
    assert_operator version, :>, before
  end
end
