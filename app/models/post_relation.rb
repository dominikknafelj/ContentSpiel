class PostRelation < ApplicationRecord
  belongs_to :post
  belongs_to :related_post, class_name: "Post"

  validate :not_self_referential
  validate :not_duplicate_reverse_pair, on: :create

  private

  def not_self_referential
    errors.add(:related_post, "can't be the same post") if post_id.present? && post_id == related_post_id
  end

  def not_duplicate_reverse_pair
    return unless post_id && related_post_id

    if PostRelation.exists?(post_id: related_post_id, related_post_id: post_id)
      errors.add(:base, "relation already exists in the opposite direction")
    end
  end
end
