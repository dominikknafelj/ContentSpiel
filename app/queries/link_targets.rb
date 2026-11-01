# The record a `ContentModel::LinkReference` names, in the one spelling of
# "which model is that type" (the rich-text mark's `type` is the same two
# words), so the public address, the validation and the editor cannot disagree.
module LinkTargets
  module_function

  def model(type)
    case type
    when "page" then Page
    when "post" then Post
    end
  end

  # What the acting person may be told of: nil for a target outside their read
  # scope and for one that does not exist, one answer for both, as the
  # `internalLink` mark's validation gives one, or saving ids one by one would
  # tell an editor which pages exist, and the editor would then show their
  # titles. A nil actor (the console, seeds, setup) reads everything, as ever.
  def readable(reference)
    relation = model(reference.type).where(id: reference.id)
    AccessControl.scope(Current.actor, "#{reference.type}s.read", relation).first
  end
end
