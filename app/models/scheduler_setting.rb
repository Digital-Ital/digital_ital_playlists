class SchedulerSetting < ApplicationRecord
  validates :name, presence: true, uniqueness: true

  def self.get(name, default = nil)
    find_by(name: name)&.value || default
  end

  def self.set(name, value)
    setting = find_or_initialize_by(name: name)
    setting.value = value.to_s
    setting.save!
  end

  def self.paused?
    get("scheduler_paused", "false") == "true"
  end

  def self.quick_updates?
    get("quick_updates", "false") == "true"
  end

  def self.pause!
    set("scheduler_paused", "true")
  end

  def self.unpause!
    set("scheduler_paused", "false")
  end

  def self.enable_quick_updates!
    set("quick_updates", "true")
  end

  def self.disable_quick_updates!
    set("quick_updates", "false")
  end
end
