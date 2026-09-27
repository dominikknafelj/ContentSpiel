require_relative "../preview_fixtures"

module Posts
  # `Posts::ResumeListComponent` (open-types spec §5): a role with an end
  # date, and one still current (a blank `end_date`, `resume_period`'s
  # "now" case).
  class ResumeListComponentPreview < ViewComponent::Preview
    def default
      page = PreviewFixtures.page(title: "Resume list preview")
      PreviewFixtures.post_list_block(page, "content_type" => "resume_entry")
      post = PreviewFixtures.post(title: "Staff Engineer", content_type: "resume_entry")
      post.assign_fields({ "company" => "Acme", "role_type" => "lead", "start_date" => "2020-01-01", "end_date" => "2023-01-01" }, locale: "en")
      post.save!

      render Posts::ResumeListComponent.new(posts: Post.where(id: post.id), page: page)
    end

    def no_end_date
      page = PreviewFixtures.page(title: "Resume list preview (current role)")
      PreviewFixtures.post_list_block(page, "content_type" => "resume_entry")
      post = PreviewFixtures.post(title: "Principal Engineer", content_type: "resume_entry")
      post.assign_fields({ "company" => "Acme", "role_type" => "ic", "start_date" => "2023-01-01", "end_date" => "" }, locale: "en")
      post.save!

      render Posts::ResumeListComponent.new(posts: Post.where(id: post.id), page: page)
    end
  end
end
