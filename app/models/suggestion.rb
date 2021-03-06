class Suggestion < ActiveRecord::Base

  belongs_to :event

  before_create :format_val

  def format_val
    self.title.downcase!
  end

  def self.add_suggestion(title)
    unless title.blank?
      title.downcase!
      title.strip!

      suggestion = self.find_or_create_by(title: title, event_id: Event.current.id)
      suggestion.update(votes: suggestion.votes + 1)

      title
    end
  end

end
